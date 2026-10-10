#!/bin/sh
set -e

build_type=$1

if [ -z "$build_type" ] || [ "$build_type" = "debug" ]; then
    echo "Starting debug build"

    mkdir -p ./build/debug
    odin build . -show-timings -debug -o:none -target:linux_amd64 -out:./build/debug/music_player

    echo "Done! Built file can be found under /build/debug"
elif [ "$build_type" = "release" ]; then
    echo "Starting release build"

    mkdir -p ./build/release
    odin build . -show-timings -o:speed -disable-assert -target:linux_amd64 -out:./build/release/music_player

    echo "Done! Built file can be found under /build/release"
fi
