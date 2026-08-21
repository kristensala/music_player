#!/usr/bin/env bash
set -e

odin build . -o:speed -disable-assert -target:linux_amd64 -out:music_player
