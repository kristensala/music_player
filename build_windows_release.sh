#!/usr/bin/env bash
set -e

mkdir -p ./build/release
odin build . -o:speed -disable-assert -target:windows_amd64 -out:./build/release/music_player.exe
