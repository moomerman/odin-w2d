// Build tool that compiles a WGPU wrapper example/game for the web.
//
// Usage:
//    odin run tools/build_web -- examples/hello
//    odin run tools/build_web -- examples/rect
//    odin run tools/build_web -- examples/texture
//
// This program:
// 1. Builds the target directory with -target:js_wasm32
// 2. Generates an index.html from a template
// 3. Copies odin.js and wgpu.js runtime files to the output folder
//
// Output goes to build/<name>-web/
package build_web

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

main :: proc() {
	print_usage: bool

	if len(os.args) < 2 {
		print_usage = true
	}

	dir: string
	serve := false
	compiler_params: [dynamic]string

	for a in os.args {
		if a == "-help" || a == "--help" {
			print_usage = true
		} else if a == "--serve" || a == "-serve" {
			serve = true
		} else if strings.has_prefix(a, "-") {
			append(&compiler_params, a)
		} else {
			dir = a
		}
	}

	if dir == "" {
		print_usage = true
	}

	if print_usage {
		fmt.eprintfln("Usage: odin run build_web -- <directory> [--serve] [-extra-params]")
		fmt.eprintfln("Example: odin run build_web -- examples/hello --serve")
		return
	}

	INDEX_TEMPLATE :: string(#load("index_template.html"))

	// Resolve the target directory relative to the build_web package's parent ().
	// The tool is run from the project root, so we need to prepend .
	wgpu_dir := ""
	target_dir := path_join({wgpu_dir, dir})

	dir_handle, dir_handle_err := os.open(target_dir)
	fmt.ensuref(
		dir_handle_err == nil,
		"Failed finding directory %v. Error: %v",
		target_dir,
		dir_handle_err,
	)

	dir_stat, dir_stat_err := os.fstat(dir_handle, context.allocator)
	fmt.ensuref(
		dir_stat_err == nil,
		"Failed checking status of directory %v. Error: %v",
		target_dir,
		dir_stat_err,
	)
	fmt.ensuref(dir_stat.type == .Directory, "%v is not a directory!", target_dir)
	os.close(dir_handle)

	dir_name := dir_stat.name

	// Create output directory.
	build_dir := "build"
	os.make_directory(build_dir, os.perm_number(0o755))
	bin_web_dir := path_join({build_dir, fmt.tprintf("%v-web", dir_name)})
	os.make_directory(bin_web_dir, os.perm_number(0o755))

	// Generate index.html from template.
	wasm_filename := fmt.tprintf("%v.wasm", dir_name)
	html_content, _ := strings.replace(INDEX_TEMPLATE, "{{TITLE}}", dir_name, -1)
	html_content, _ = strings.replace(html_content, "{{WASM_FILENAME}}", wasm_filename, -1)

	html_path := path_join({bin_web_dir, "index.html"})
	write_html_err := os.write_entire_file(html_path, transmute([]u8)html_content)
	fmt.ensuref(write_html_err == nil, "Failed writing %v. Error: %v", html_path, write_html_err)
	fmt.printfln("Wrote %v", html_path)

	// Find odin root for JS runtime files.
	_, odin_root_stdout, _, odin_root_err := os.process_exec(
		{command = {"odin", "root"}},
		allocator = context.allocator,
	)
	ensure(odin_root_err == nil, "Failed fetching 'odin root' (is Odin in PATH?)")
	odin_root := strings.trim_right_space(string(odin_root_stdout))

	// Copy odin.js
	odin_js_path := path_join({odin_root, "core", "sys", "wasm", "js", "odin.js"})
	fmt.ensuref(os.exists(odin_js_path), "odin.js not found at: %v", odin_js_path)
	os.copy_file(path_join({bin_web_dir, "odin.js"}), odin_js_path)
	fmt.printfln("Copied odin.js")

	// Copy wgpu.js
	wgpu_js_path := path_join({odin_root, "vendor", "wgpu", "wgpu.js"})
	fmt.ensuref(os.exists(wgpu_js_path), "wgpu.js not found at: %v", wgpu_js_path)
	os.copy_file(path_join({bin_web_dir, "wgpu.js"}), wgpu_js_path)
	fmt.printfln("Copied wgpu.js")

	// Build the wasm.
	INITIAL_MEMORY_PAGES :: 2000
	MAX_MEMORY_PAGES :: 65536
	INITIAL_MEMORY_BYTES :: INITIAL_MEMORY_PAGES * MAX_MEMORY_PAGES
	MAX_MEMORY_BYTES :: MAX_MEMORY_PAGES * MAX_MEMORY_PAGES

	wasm_out_path := path_join({bin_web_dir, wasm_filename})

	linker_flags := fmt.tprintf(
		"--export-table --import-memory --initial-memory=%v --max-memory=%v",
		INITIAL_MEMORY_BYTES,
		MAX_MEMORY_BYTES,
	)

	build_command: [dynamic]string
	append(
		&build_command,
		..[]string {
			"odin",
			"build",
			target_dir,
			fmt.tprintf("-out:%v", wasm_out_path),
			"-target:js_wasm32",
			"-o:size",
			fmt.tprintf("-extra-linker-flags:%v", linker_flags),
		},
	)
	append(&build_command, ..compiler_params[:])

	fmt.printfln("Building %v ...", target_dir)

	build_status, build_stdout, build_stderr, _ := os.process_exec(
		{command = build_command[:]},
		allocator = context.allocator,
	)

	if len(build_stdout) > 0 {
		fmt.print(string(build_stdout))
	}

	if len(build_stderr) > 0 {
		fmt.print(string(build_stderr))
	}

	if build_status.exit_code != 0 {
		fmt.eprintfln("Build failed with exit code %v", build_status.exit_code)
		os.exit(build_status.exit_code)
	}

	fmt.printfln("Build complete: %v/", bin_web_dir)

	if serve {
		PORT :: "8000"
		fmt.printfln("Serving at http://localhost:%v", PORT)
		argv := [?]cstring {
			"python3",
			"-m",
			"http.server",
			PORT,
			"-d",
			strings.clone_to_cstring(bin_web_dir),
			nil,
		}
		posix.execvp("python3", raw_data(&argv))
		// execvp only returns on failure.
		fmt.eprintfln("Failed to start server (is python3 in PATH?)")
		os.exit(1)
	} else {
		fmt.printfln("Serve with:    python3 -m http.server -d %v", bin_web_dir)
	}
}

path_join :: proc(parts: []string) -> string {
	p, err := os.join_path(parts, allocator = context.allocator)
	fmt.ensuref(err == nil, "Failed joining path: %v", err)
	return p
}
