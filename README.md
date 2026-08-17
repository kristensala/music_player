# music_player

![Demo](/images/demo.gif)

- File dialog from https://github.com/btzy/nativefiledialog-extended
- Bindings for nativefiledialog-extended in odin from https://github.com/ivansouzamf/nativefiledialog-odin

# TODO
- [ ] Notification of currently playing track when track changes or player starts playing (DBUS or https://github.com/GNOME/libnotify) (https://specifications.freedesktop.org/notification/latest/)
- [ ] Support playlist creation ({LIBRARY_PATH}/mppl0 etc)
- [ ] Search
- [ ] Unix domain socket (IPC) for playback control or dbus MPRIS
- [ ] Taglib text encoding bug (' is not properly encoded, returns ?)
- [ ] Command Palette for settings etc
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
