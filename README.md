# music_player

![Demo](/images/demo.png)
![Memory](/images/memory.png)

# TODO
- [ ] Fix the order of the tracks in an album (use metadata track nr if it is set, else use file name)
- [ ] Shuffle queue
- [ ] Support playlist creation ({LIBRARY_PATH}/mppl0 etc)
- [ ] Search
- [ ] Music visualizer (mesh style in the middle of the screen - background)
- [ ] Unix domain socket (IPC) for playback control
- [ ] Taglib text encoding bug (' is not properly encoded, returns ?)
- [ ] Prompt enter library location when not found in config
- [ ] File dialog lib: https://github.com/btzy/nativefiledialog-extended
- [ ] Command Palette for settings etc
- [ ] Maybe?? add podcast rss feed??
- [x] Repeat song or queue button
- [x] Logging and fix error handling
- [x] Debug cache invalidation (Something lives longer than it has to)
- [x] Fix taglib mp3 major version 2 parsing
- [x] Per artist filtering
- [x] Scrolling is broken
- [x] Display album art
- [x] Render only what is visible to the user
- [x] Create/Read config file ~/.config/music_player/config
