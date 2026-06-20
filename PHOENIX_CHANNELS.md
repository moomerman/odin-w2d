# Phoenix Channels client for Odin — research notes

Notes from investigating how to build an Elixir Phoenix Channels client in
Odin (June 2026). Verified end-to-end on macOS with a live `wss://` echo
round-trip using `vendor:curl`.

## Summary

- No off-the-shelf Phoenix Channels client exists for Odin; the protocol
  layer must be hand-written, but it is small (a few hundred lines).
- The real decision is the WebSocket transport underneath it:
  - **Desktop:** `vendor:curl` (in Odin since at least dev-2026-06) ships the
    full libcurl WebSocket API — no hand-rolled bindings needed. Verified
    working, with two macOS link gotchas (below).
  - **Web (`js` target):** the browser's native `WebSocket` via JS foreign
    imports — the browser handles TLS and framing.
- Natural architecture for this engine: a small transport interface selected
  by `#+build` tags (curl on desktop, browser WebSocket on js), with a
  hand-written `phoenix` package on top exposing connect/join/push and
  per-frame event polling.

## The Phoenix protocol layer

Phoenix Channels over WebSocket is just JSON frames. Connect to
`/socket/websocket?vsn=2.0.0` to get the V2 serializer, where every message
is a 5-element array:

```
[join_ref, ref, topic, event, payload]
```

The client needs:

- a monotonically increasing ref counter
- `phx_join` / `phx_leave` events to enter/exit topics
- matching `phx_reply` responses back to pending refs (payload carries
  `status` + `response`)
- a heartbeat push to topic `"phoenix"`, event `"heartbeat"`, every ~30s
- rejoin-with-backoff on `phx_error` / disconnect

`core:encoding/json` covers serialization. The API maps well onto an
immediate-mode style: poll for channel events once per frame rather than
callbacks. Skip Phoenix's longpoll fallback transport — when we control both
ends, WebSocket-only is fine.

## Desktop transport: `vendor:curl`

`$(odin root)/vendor/curl/curl_websockets.odin` binds the libcurl WebSocket
API (`ws_send`, `ws_recv`, `ws_meta`, `ws_start_frame`). The flow is:
set `CONNECT_ONLY = 2` on an easy handle, `easy_perform` to do the TLS +
upgrade handshake, then `ws_send`/`ws_recv` directly.

`ws_recv` is **non-blocking** — it returns `.E_AGAIN` when nothing is
pending — so it can be polled once per frame with zero threads. Great fit
for a game loop.

Gotchas:

- Result codes are prefixed in the Odin binding: `.E_OK` / `.E_AGAIN`,
  not `.OK` / `.AGAIN`.
- **Partial frames:** large payloads can arrive split across `ws_recv`
  calls. Check `meta.bytesleft` and buffer until it reaches zero before
  handing the JSON to the parser.

### macOS link gotchas (both verified)

1. **Apple's system libcurl has WebSocket disabled.** macOS ships curl 8.7.1
   with no `ws`/`wss` in its protocol list, and the SDK's `libcurl.tbd` is
   what `-lcurl` resolves to by default. Homebrew's curl (8.20.0 here,
   OpenSSL-backed) has `ws wss` enabled. Point the linker at it:

   ```
   -extra-linker-flags:"-L/opt/homebrew/opt/curl/lib"
   ```

   `otool -L` then shows the binary depends on
   `/opt/homebrew/opt/curl/lib/libcurl.4.dylib` — correct.

2. **The vendor binding hardcodes mbedTLS on Darwin.** Its foreign import
   adds `-lmbedx509 -lmbedcrypto`, assuming an mbedTLS-built curl. With an
   OpenSSL-built Homebrew curl and no mbedTLS installed, linking fails:
   `ld: library 'mbedx509' not found`. Cleanest workaround: empty stub
   static archives in an extra `-L` dir — links clean and adds no false
   runtime dependency (macOS `ar` refuses empty archives, hence the dummy
   object):

   ```sh
   mkdir -p stub && cd stub
   echo "static int _unused;" > empty.c
   clang -c empty.c -o empty.o
   ar rcs libmbedx509.a empty.o
   ar rcs libmbedcrypto.a empty.o
   ```

   (`brew install mbedtls` also satisfies the linker but bakes unnecessary
   dylib load commands into the binary. The long-term fix is upstream: make
   the mbedTLS libs in `vendor/curl/curl.odin` conditional or `#config`-able.)

Full build command for the test program:

```sh
odin build . -out:wstest \
  -extra-linker-flags:"-L/opt/homebrew/opt/curl/lib -L./stub"
```

### Verified working example

Connects to a public echo server over `wss://`, sends a text frame, and
polls until the echo comes back:

```odin
package main

import "core:c"
import "core:time"
import "core:fmt"
import curl "vendor:curl"

main :: proc() {
	fmt.println("libcurl:", curl.version())

	h := curl.easy_init()
	if h == nil {
		fmt.eprintln("easy_init failed")
		return
	}
	defer curl.easy_cleanup(h)

	curl.easy_setopt(h, .URL, cstring("wss://echo.websocket.org"))
	curl.easy_setopt(h, .CONNECT_ONLY, c.long(2)) // WebSocket mode

	res := curl.easy_perform(h)
	if res != .E_OK {
		fmt.eprintln("connect failed:", res)
		return
	}
	fmt.println("connected!")

	msg := "hello from odin"
	sent: c.size_t
	res = curl.ws_send(h, raw_data(msg), len(msg), &sent, 0, curl.WS_TEXT)
	fmt.println("send:", res, "bytes:", sent)

	buf: [1024]u8
	meta: ^curl.ws_frame
	for _ in 0 ..< 10 {
		got: c.size_t
		res = curl.ws_recv(h, &buf[0], len(buf), &got, &meta)
		if res == .E_OK {
			fmt.println("recv:", string(buf[:got]))
			if string(buf[:got]) == msg {
				fmt.println("echo round-trip OK")
				return
			}
		} else if res == .E_AGAIN {
			time.sleep(100 * time.Millisecond)
		} else {
			fmt.eprintln("recv failed:", res)
			return
		}
	}
}
```

Output:

```
libcurl: libcurl/8.20.0 OpenSSL/3.6.2 zlib/1.2.12 ...
connected!
send: E_OK bytes: 15
recv: Request served by 4d896d95b55478
recv: hello from odin
echo round-trip OK
```

(In a real client, replace the `time.sleep` polling loop with one
`ws_recv` poll per frame.)

## Other transport options considered (and rejected)

- **Existing Odin libraries** — both young; reference material at best:
  - [websocket-client-odin](https://github.com/FreerGit/websocket-client-odin)
    — simple client, OpenSSL-based, wss-only.
  - [odin-websocket](https://github.com/ZealousProgramming/odin-websocket)
    — basic implementation, still working toward RFC 6455 compliance.
- **Pure Odin over `core:net`** — the client side of RFC 6455 is easy
  (HTTP upgrade handshake, XOR masking, frame headers), but Odin's core
  library has no TLS, so `wss://` means binding OpenSSL/mbedTLS anyway —
  at which point curl is less work.
- **Heavier C libs** (libwebsockets, mongoose) — more surface area than a
  client-only use case needs; existing bindings like
  [odin-wsserver](https://github.com/saenai255/odin-wsserver) are
  server-oriented.

## Open items

- Upstream a fix to Odin's `vendor/curl` Darwin link line (conditional
  mbedTLS libs).
- The `-extra-linker-flags` + stub-archive setup needs wiring into the
  justfile if/when this lands in the engine.
- Windows/Linux note: `vendor/curl` bundles `lib/libcurl.lib` on Windows
  and links `system:curl` + mbedTLS on Linux — same "is WebSocket enabled
  in the system curl?" question applies there, unverified.
