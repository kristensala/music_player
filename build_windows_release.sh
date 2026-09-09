#!/usr/bin/env bash
set -e

mkdir -p ./build/release
odin build . -o:aggressive -no-bounds-check -disable-assert -no-type-assert -subsystem:windows -out:./build/release/music_player.exe
