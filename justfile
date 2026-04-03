example := "hello"

vet_flags := "-vet -strict-style -vet-semicolon -vet-cast -vet-using-param -vet-shadowing -warnings-as-errors"

run:
    odin run examples/{{example}}

run-debug:
    odin run examples/{{example}} -debug

run-release:
    odin run examples/{{example}} -o:aggressive

build:
    odin build examples/{{example}}

build-debug:
    odin build examples/{{example}} -debug

build-release:
    odin build examples/{{example}} -o:aggressive -out:{{example}}

build-web:
    odin run tools/build_web -- examples/{{example}}

build-web-serve:
    odin run tools/build_web -- examples/{{example}} --serve

check-example:
    odin check examples/{{example}} {{vet_flags}} -vet-packages:main,game

check:
    odin check . -no-entry-point {{vet_flags}} -vet-packages:engine,core,backend,renderer_wgpu,window_darwin,window_sdl3,window_js,audio_miniaudio,audio_webaudio

check-tools:
    odin check tools/build_web {{vet_flags}} -vet-packages:build_web
    odin check tools/time_tracker -no-entry-point {{vet_flags}} -vet-packages:time_tracker
    odin check tools/tracking_allocator -no-entry-point {{vet_flags}} -vet-packages:tracking_allocator

check-all-examples:
    #!/usr/bin/env bash
    for dir in examples/*/; do
        example=$(basename "$dir")
        echo "Checking $example..."
        just example="$example" check-example
    done

format:
    odinfmt -w .

verify: format check check-tools check-all-examples
