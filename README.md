# music_player

![Demo](/images/demo.gif)

## Info
- `Ctrl-p` opens command palette
- Notifications are triggered through dbus on Linux. No implementation on Windows at the moment
    - For notifications to work on linux, `libsystemd-dev` needs to be installed
- For music to be organized nicely, the metadata of the tracks needs to be consistent. You can use `https://picard.musicbrainz.org/` to fix the tracks
- Player assumes that each album is in its own folder and for album art to work, each folder needs to contain an image named cover.jpg/png/jpeg. It specifically looks for a file named cover.{ext} and is case sensitive
- For audio control, `miniaudio` is used
- Rendering the whole UI: `raylib`
- Custom taglib implementation (no library) to read the metadata of .mp3 and .flac files. (No WAV at the moment, but will come)
- Shuffle queue is a simple `Fisher-Yates shuffle` algorithm

## Extras
- File dialog from https://github.com/btzy/nativefiledialog-extended
- Bindings for nativefiledialog-extended in odin from https://github.com/ivansouzamf/nativefiledialog-odin
