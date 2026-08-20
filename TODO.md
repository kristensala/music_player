# TODO
- [ ] Add tracks as favourite (part of playlist support)
- [ ] Support playlist creation ({LIBRARY_PATH}/mppl0 etc)
- [ ] Search
- [ ] Unix domain socket (IPC) for playback control or dbus MPRIS
- [ ] Taglib text encoding bug (' is not properly encoded, returns ?)
- [ ] Command Palette for settings etc
- [x] Use sdbus over libdbus-1. Way more concise
- [x] Fix the order of the tracks in an album (use metadata track nr if it is set, else use file name)
- [x] Shuffle queue
- [x] Show album art of the currently playing track
- [x] Prompt enter library location when not found in config (https://github.com/btzy/nativefiledialog-extended)
- [x] Repeat song or queue button
- [x] Logging and fix error handling
- [x] Debug cache invalidation (Something lives longer than it has to)
- [x] Fix taglib mp3 major version 2 parsing
- [x] Per artist filtering
- [x] Scrolling is broken
- [x] Display album art
- [x] Render only what is visible to the user
- [x] Create/Read config file ~/.config/music_player/config

# Interesting additions (@todo)
- [ ] Music visualizer (mesh style in the middle of the screen - background)
- [ ] Maybe?? add podcast rss feed??
