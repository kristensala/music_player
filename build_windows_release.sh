#!/usr/bin/env bash
set -e

odin build . -o:speed -disable-assert -target:windows_amd64 -out:music_player.exe
