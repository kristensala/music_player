# music_player

![Demo](/images/demo.png)
![Memory](/images/memory.png)

# TODO
- [ ] Windows: use Win32 api to scan the music library
- [ ] Unix domain socket (IPC) for playback control
- [ ] Search
- [ ] Taglib text encoding bug (' is not properly encoded, returns ?)
- [ ] Maybe?? add podcast rss feed??
- [ ] Shuffle queue
- [x] Repeat song or queue button
- [ ] Logging and fix error handling
- [ ] Support playlist creation ({LIBRARY_PATH}/mppl0 etc)
- [x] Debug cache invalidation (Something lives longer than it has to)
- [x] Fix taglib mp3 major version 2 parsing
- [x] Per artist filtering
- [ ] Scrolling is broken
- [x] Display album art
- [x] Render only what is visible to the user
- [ ] Prompt enter library location when not found in config
- [x] Create/Read config file ~/.config/music_player/config
- [ ] Command Palette for settings etc
- [ ] File dialog lib: https://github.com/btzy/nativefiledialog-extended
