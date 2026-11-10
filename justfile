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
    odin check . -no-entry-point {{vet_flags}} -vet-packages:engine,core,backend,renderer_wgpu,window_darwin,window_sdl3,window_js,window_null,audio_miniaudio,audio_webaudio,gamepad_sdl3,gamepad_js

check-ui:
    odin check ui -no-entry-point {{vet_flags}} -vet-packages:ui

check-tools:
    odin check tools/build_web {{vet_flags}} -vet-packages:build_web
    odin check tools/time_tracker -no-entry-point {{vet_flags}} -vet-packages:time_tracker
    odin check tools/tracking_allocator -no-entry-point {{vet_flags}} -vet-packages:tracking_allocator

check-tests:
    odin check tests/render {{vet_flags}} -vet-packages:main
    odin check tests/automation {{vet_flags}} -vet-packages:main

# Headless tests (no window; needs a GPU): render and input at 1x and 2x
# scale, then an ordinary program driven by a W2D_SCRIPT.
test:
    odin build tests/render -out:build/tests-render
    ./build/tests-render 1
    ./build/tests-render 2
    odin build tests/automation -out:build/tests-automation
    rm -f build/automation-shot.png
    W2D_HEADLESS=1 W2D_SCRIPT=tests/automation/script.txt ./build/tests-automation
    test -s build/automation-shot.png

# Run an example with no window and save a frame: just example=shapes shot
# writes build/shots/shapes.png after `frames` frames. See automation.odin.
shot frames="60":
    mkdir -p build/shots
    odin build examples/{{example}} -out:build/{{example}}
    W2D_HEADLESS=1 W2D_FRAMES={{frames}} W2D_SCREENSHOT=build/shots/{{example}}.png ./build/{{example}}

check-all-examples:
    #!/usr/bin/env bash
    for dir in examples/*/; do
        example=$(basename "$dir")
        echo "Checking $example..."
        just example="$example" check-example
    done

format:
    odinfmt -w .

verify: format check check-ui check-tools check-tests check-all-examples test
