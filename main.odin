package main

import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:sort"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:mem"
import "core:path/filepath"
import "core:os"
import tl "taglib"

SCROLL_INCREMENT :: 5 // five rows
BOTTOM_BAR_PADDING :: 50
FONT_18 :: 18
FONT_20 :: 20
FONT_30 :: 30
PLAYBACK_BUTTON_SIZE :: 30
SIDE_PANEL_ROW_HEIGHT :: 35
ROW_HEIGHT :: 40
TRACK_LIST_OFFSET_X :: 250
CACHE_MAX_CAPACITY :: 15

ALL_ARTISTS_OPTION :: "All Artists"

Track_Idx :: i32

Row :: struct {
    is_album_row : bool, // if true then track is nil
    album_idx: i32,
    track: ^Track,
}

Playlist :: struct {
    title: string,
    playlist_file_path: string,
    tracks: [dynamic]^Track,
}

Side_Panel :: struct {
    side_panel_rect: rl.Rectangle,
    side_panel_scroll_offset: f32,

    side_panel_options_rect: rl.Rectangle,
    side_panel_option_content_rect: rl.Rectangle,

    side_panel_options: [2]Side_Panel_Option,
    selected_side_panel_option: Side_Panel_Option
}

Main_Panel :: struct {
    main_panel_rect: rl.Rectangle,
    main_panel_scroll_offset: i32,

    rows: [dynamic]^Row,
    content_max_height: i32, // in pixels
}

Playback_Controls_Panel :: struct {
    playback_controls_panel_rect: rl.Rectangle,

    play_button_texture: rl.Texture2D,
    pause_button_texture: rl.Texture2D,
    next_button_texture: rl.Texture2D,
    previous_button_texture: rl.Texture2D
}

App_State :: struct {
    using main_panel: Main_Panel,
    using side_panel: Side_Panel,
    using playback_controls_panel: Playback_Controls_Panel,

    fonts: map[i32]rl.Font,

    library_path: string,
    is_library_path_set: bool,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,

    playlist_path: string,
    playlists: [dynamic]Playlist,

    queue: [dynamic]Track_Idx, // @todo: not implemented

    default_album_cover_texture: rl.Texture2D,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing_track: ^Track,

    // filtering
    artist_list: [dynamic]cstring,
    current_selected_artist: cstring, // nil means show all the tracks

    album_art_cache: Album_Art_Cache,
    album_art_load_queue: [dynamic]i32, // ref album idx

    current_frame_rendered: u64 // current rendered frame
}

Album_Art_Cache :: struct {
    entries: [CACHE_MAX_CAPACITY]^Album_Art_Cache_Entry,
    count: i32,
}

Album_Art_Cache_Entry :: struct {
    texture: rl.Texture2D,
    album_idx: i32,

    frame: u64 // last frame it was rendered
}

AudioState :: enum i32 {
    Stopped = 0,
    Playing = 1,
    Paused = 2
}

Track :: struct {
    title: cstring,
    artist: cstring,
    album_title: cstring,
    album_idx: i32, // @todo: use ^Album, then I can sort the Album list
    file_path: cstring,
    file_name: cstring,

    order_nr_in_album: i32
}

Album :: struct {
    title: cstring,
    artist: cstring,

    cover_art_path: cstring,
    cover_art_cache_entry_idx: i32,

    track_indices: [dynamic]Track_Idx // reference to the app_state.tracks @todo: should use [dynamic]^Track then I can sort the list of tracks
}

Side_Panel_Option :: enum i32 {
    Artist_List = 0,
    Playlists = 1,
    All_Music = 2 // @todo: remove all artists option from artist list and add it to the side_panel options instead. As "All Music"
}

@private
@require_results
init_state :: proc() -> ^App_State {
    app_state := new(App_State)
    app_state.is_library_path_set = false
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.selected_side_panel_option = .Artist_List // @todo: All_Music once implemented

    load_assets(app_state)
    load_config(app_state)

    playlist_path, err := filepath.join({app_state.library_path, ".mppl"}, context.allocator)
    assert(err == nil)
    app_state.playlist_path = playlist_path

    app_state.side_panel_rect = rl.Rectangle{
        x = 0,
        y = 0,
        width = 300
    }
    app_state.side_panel_options_rect = rl.Rectangle{
        x = app_state.side_panel_rect.x,
        y = app_state.side_panel_rect.y,
        height = 100,
        width = app_state.side_panel_rect.width,
    }
    app_state.side_panel_option_content_rect = rl.Rectangle{
        x = app_state.side_panel_rect.x,
        y = app_state.side_panel_rect.y + app_state.side_panel_options_rect.height,
        width = app_state.side_panel_rect.width,
    }

    app_state.main_panel_rect = rl.Rectangle{ x = app_state.side_panel_rect.width + 20, y = 20}
    app_state.playback_controls_panel_rect = rl.Rectangle{ x = 0, height = 170 }

    if app_state.is_library_path_set {
        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        walk_music_dir(app_state, app_state.library_path)
        build_rows(app_state) // for ui
    }

    return app_state
}

main :: proc() {
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1800, 1250, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    app_state := init_state()

    // @nocheckin: testing
    {
        /*create_playlist(app_state, "test")
        tmp_playlist := &app_state.playlists[0]
        tmp_track := &app_state.tracks[0]

        add_track_to_playlist(tmp_playlist, tmp_track, app_state.library_path)*/
        init_playlists_from_playlist_files(app_state)
    }

    engine_init_result := ma.engine_init(nil, &app_state.ma_engine)
    if engine_init_result != .SUCCESS {
        fmt.println("Could not init Mini audio engine: ", engine_init_result)
        ma.engine_uninit(&app_state.ma_engine)
        return
    }
    defer ma.engine_uninit(&app_state.ma_engine)

    was_focused := true
    for !rl.WindowShouldClose() {
        // hack to lower CPU usage when window is not focused
        is_focused := rl.IsWindowFocused()
        if is_focused != was_focused {
            rl.SetTargetFPS(is_focused ? 60 : 10)
            was_focused = is_focused
        }

        if app_state.is_library_path_set {
            update_main(app_state)
            update_layout(app_state)
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        if app_state.is_library_path_set {
            draw_main(app_state)
        } else {
            draw_insert_library_path_screen(app_state)
        }

        rl.EndDrawing()
    }

    // cleanup
    {
        destroy_state(app_state)
    }
}


@(private = "file")
update_main :: proc(app_state: ^App_State) {
    app_state.current_frame_rendered += 1

    invalidate_cache(app_state)
    process_album_art_queue(app_state)
    handle_keyboard_events(app_state)

    if ma.sound_at_end(app_state.ma_sound) {
        handle_next_song_pick(app_state)
    }
}

@private
destroy_state :: proc(app_state: ^App_State) {
    ma.sound_uninit(app_state.ma_sound)

    delete(app_state.rows)
    delete(app_state.artist_list)

    for entry in app_state.album_art_cache.entries {
        if entry == nil do continue
        rl.UnloadTexture(entry.texture)
    }

    for a in app_state.albums {
        delete(a.track_indices)
        delete(a.cover_art_path)
    }
    delete(app_state.albums)

    for t in app_state.tracks {
        delete(t.file_name)
        delete(t.file_path)
        delete(t.title)
        delete(t.artist)
        delete(t.album_title)
    }
    delete(app_state.tracks)


    for p in app_state.playlists {
        delete(p.tracks)
    }
    delete(app_state.playlists)


    rl.UnloadTexture(app_state.default_album_cover_texture)
    rl.UnloadTexture(app_state.play_button_texture)
    rl.UnloadTexture(app_state.pause_button_texture)
    rl.UnloadTexture(app_state.next_button_texture)
    rl.UnloadTexture(app_state.previous_button_texture)

    for key, value in app_state.fonts {
        rl.UnloadFont(value)
    }
    delete(app_state.fonts)
    delete(app_state.library_path)
    delete(app_state.playlist_path)

    free(app_state)
}

@(private = "file")
load_assets :: proc(app_state: ^App_State) {
    // fonts
    {
        font_18 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_18, nil, 0)
        font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_20, nil, 0)
        font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_30, nil, 0)

        fonts := make(map[i32]rl.Font)
        fonts[FONT_18] = font_18
        fonts[FONT_20] = font_20
        fonts[FONT_30] = font_30

        app_state.fonts = fonts
    }

    // album art placeholder
    {
        album_placeholder_img := rl.LoadImage("./res/album_placeholder.png")
        rl.ImageResize(&album_placeholder_img, 200, 200)
        app_state.default_album_cover_texture = rl.LoadTextureFromImage(album_placeholder_img)
        rl.UnloadImage(album_placeholder_img)
    }

    // Load play button image
    {
        play_btn_img := rl.LoadImage("./res/play.png")
        rl.ImageResize(&play_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.play_button_texture =  rl.LoadTextureFromImage(play_btn_img)
        rl.UnloadImage(play_btn_img)
    }

    // Load pause button image
    {
        pause_btn_img := rl.LoadImage("./res/pause.png")
        rl.ImageResize(&pause_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.pause_button_texture =  rl.LoadTextureFromImage(pause_btn_img)
        rl.UnloadImage(pause_btn_img)
    }

    // Load next button image
    {
        next_btn_img := rl.LoadImage("./res/next.png")
        rl.ImageResize(&next_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.next_button_texture =  rl.LoadTextureFromImage(next_btn_img)
        rl.UnloadImage(next_btn_img)
    }

    // Load previous button image
    {
        prev_btn_img := rl.LoadImage("./res/previous.png")
        rl.ImageResize(&prev_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.previous_button_texture =  rl.LoadTextureFromImage(prev_btn_img)
        rl.UnloadImage(prev_btn_img)
    }
}

@(private = "file")
create_config_file :: proc(path: string) {
    config_file, err := os.create(path)
    if err != nil {
        fmt.println("Could not create config file")
        return
    }
    defer os.close(config_file)

    s := "LIBRARY_PATH="
    _, err = os.write(config_file, transmute([]byte)s)
    if err != nil {
        fmt.eprintln("Could not write to config file")
        return
    }

}

// @todo: windows
@(private = "file")
load_config :: proc(app_state: ^App_State) {
    home_dir, err  := os.user_home_dir(context.allocator)
    if err != nil {
        fmt.eprintln(#procedure, "Failed to get user_home_dir: ", err)
        return
    }

    defer delete(home_dir)

    config_path, join_err := filepath.join({home_dir, ".config", "music_player"}, context.allocator)
    assert(join_err == nil, "Probably programmer error")
    defer delete(config_path)

    // @todo: handle err
    config_file_path, e := filepath.join({config_path, "config"}, context.allocator)
    assert(e == nil, "Probably programmer error")
    defer delete(config_file_path)

    file_info, file_info_err := os.stat(config_path, context.allocator)
    defer os.file_info_delete(file_info, context.allocator)

    if file_info_err == nil && file_info.type == .Directory {
        if os.exists(config_file_path) {
            file_data, err := os.read_entire_file_from_path(config_file_path, context.allocator)
            if err != nil {
                fmt.eprintln("Could not read config file")
                return
            }
            defer delete(file_data)

            it := string(file_data)
            for line in strings.split_lines_iterator(&it) {
                // process line
                if strings.has_prefix(line, "LIBRARY_PATH=") {
                    library_path := line[len("LIBRARY_PATH="):]
                    if len(library_path) > 0 {
                        app_state.library_path = strings.clone(library_path)
                        app_state.is_library_path_set = true
                    }
                }
            }
        } else {
            create_config_file(config_file_path)
        }
    } else {
        mkdir_err := os.mkdir(config_path)
        if mkdir_err != nil {
            fmt.eprintln("Could not create music_player directory")
            return
        }

        create_config_file(config_file_path)
    }
}

@private
handle_keyboard_events :: proc(app_state: ^App_State) {
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
        if app_state.ma_sound == nil {
            return
        }

        handle_play_pause(app_state)
    }
}

@(private = "file")
walk_music_dir :: proc(app_state: ^App_State, path: string) {
    data, err := os.read_directory_by_path(path, 0, context.allocator)
    if err != nil {
        fmt.printf("Could not read the dir", err)
        return
    }
    defer delete(data)

    album_map := make(map[cstring]int)
    defer delete(album_map)

    current_album: ^Album

    for d in data {
        if d.type == .Directory {
            walk_music_dir(app_state, d.fullpath)
        } else if d.type == .Regular {
            if filepath.ext(d.fullpath) == ".mp3" || filepath.ext(d.fullpath) == ".flac" || filepath.ext(d.fullpath) == ".wav" {
                // @todo: if image found `cover.jpeg/png` save to a map with base path as key
                // map[string]string and value as path to the cover art
                // after the tracks are found, use track file_path and match with the cover art path

                //fmt.printfln(d.fullpath)
                tag, tl_error := tl.get_tag(d.fullpath)
                //fmt.printfln("md.title len=%d value=%q", len(tag.title), tag.title)

                track := Track{
                    title = strings.clone_to_cstring(tag.title),
                    artist = strings.clone_to_cstring(tag.artist),
                    album_title = strings.clone_to_cstring(tag.album),
                    file_name = strings.clone_to_cstring(d.name),
                    file_path = strings.clone_to_cstring(d.fullpath)
                }

                // create album
                {
                    idx, album_exists := album_map[track.album_title]
                    if !album_exists {
                        idx = len(app_state.albums)

                        album := Album{
                            title = track.album_title,
                            artist = track.artist,
                            cover_art_cache_entry_idx = -1
                        }
                        append(&app_state.albums, album)
                        album_map[track.album_title] = idx
                    }
                    track.album_idx = i32(idx)

                    track_idx := len(app_state.tracks)
                    append(&app_state.albums[idx].track_indices, i32(track_idx))

                    track_pos := len(app_state.albums[idx].track_indices) - 1
                    track.order_nr_in_album = i32(track_pos)

                    current_album = &app_state.albums[len(app_state.albums) - 1]
                }

                append(&app_state.tracks, track)
                tl.tag_destroy(&tag)

                if !slice.contains(app_state.artist_list[:], current_album.artist) {
                    append(&app_state.artist_list, current_album.artist)
                }

            } else if filepath.ext(d.fullpath) == ".jpg" || filepath.ext(d.fullpath) == ".jpeg" || filepath.ext(d.fullpath) == ".png" {
                // found an image. Assume this is the cover for the album
                if current_album != nil {
                    current_album.cover_art_path = strings.clone_to_cstring(d.fullpath)
                }
            }
        }
    }

    // @todo: ignore case
    sort.quick_sort(app_state.artist_list[1:])
}

@private
build_rows :: proc(app_state: ^App_State) {
    rows : [dynamic]^Row
    content_height : i32 = 0

    for &album, album_idx in app_state.albums {
        if app_state.current_selected_artist != nil {
            if album.artist != app_state.current_selected_artist do continue
        }

        album_title_row := new(Row)
        album_title_row.is_album_row = true
        album_title_row.album_idx = i32(album_idx)

        append(&rows, album_title_row)

        content_height += ROW_HEIGHT

        album_content_height : i32 = 0
        for track_idx in album.track_indices {
            track := &app_state.tracks[track_idx]
            assert(track != nil)

            track_row := new(Row)
            track_row.track = track

            append(&rows, track_row)

            //content_height = pos_y + ROW_HEIGHT
            album_content_height += ROW_HEIGHT
        }

        if album_content_height < COVER_SIZE {
            diff := (COVER_SIZE - album_content_height) / ROW_HEIGHT
            for i in 0..<diff {
                append(&rows, nil)
                album_content_height += ROW_HEIGHT
            }
        }

        content_height += album_content_height // padding after the album
    }

    app_state.rows = rows
    app_state.content_max_height = content_height
}

@private
least_used_cover_art_idx :: proc(app_state: ^App_State) -> (cache_entry_idx: i32, cache_entry: ^Album_Art_Cache_Entry) {
    smallest_usage : u64
    entry_idx: i32
    e : ^Album_Art_Cache_Entry

    for entry, idx in app_state.album_art_cache.entries {
        if idx == 0 {
            smallest_usage = entry.frame
            entry_idx = i32(idx)
            e = entry
            continue
        }

        if entry.frame < smallest_usage {
            smallest_usage = entry.frame
            entry_idx = i32(idx)
            e = entry
        }
    }

    return entry_idx, e
}

@private
request_cover_load :: proc(queue: ^[dynamic]i32, album_idx: i32) {
    if len(queue) == CACHE_MAX_CAPACITY do return

    is_in_queue := false
    for item in queue {
        if item == album_idx {
            is_in_queue = true
            return
        }
    }
    if is_in_queue do return
    append(queue, album_idx)
}

@private
process_album_art_queue :: proc(app_state: ^App_State) {
    for album_idx, idx in app_state.album_art_load_queue {
        album := &app_state.albums[album_idx]

        fmt.println("loading album art for: ", album.title)

        if len(album.cover_art_path) > 0 {
            // cache is full
            if app_state.album_art_cache.count >= CACHE_MAX_CAPACITY {
                cache_entry_idx, cache_entry := least_used_cover_art_idx(app_state)

                least_used_album := &app_state.albums[cache_entry.album_idx]
                least_used_album.cover_art_cache_entry_idx = -1

                current_entry := app_state.album_art_cache.entries[cache_entry_idx]
                rl.UnloadTexture(current_entry.texture)

                app_state.album_art_cache.entries[cache_entry_idx] = {}
                app_state.album_art_cache.count -= 1

                img := rl.LoadImage(album.cover_art_path)
                rl.ImageResize(&img, 200, 200)
                texture := rl.LoadTextureFromImage(img)
                rl.UnloadImage(img)

                new_cache_entry := new(Album_Art_Cache_Entry)
                new_cache_entry.album_idx = album_idx
                new_cache_entry.texture = texture
                new_cache_entry.frame = app_state.current_frame_rendered

                app_state.album_art_cache.entries[cache_entry_idx] = new_cache_entry
                album.cover_art_cache_entry_idx = cache_entry_idx
                app_state.album_art_cache.count += 1
            } else {
                img := rl.LoadImage(album.cover_art_path)
                rl.ImageResize(&img, 200, 200)
                texture := rl.LoadTextureFromImage(img)
                rl.UnloadImage(img)

                idx := -1
                for e, i in app_state.album_art_cache.entries {
                    // look for the first empty entry
                    if e == nil {
                        idx = i
                    }
                }
                if idx >= 0 {
                    new_cache_entry := new(Album_Art_Cache_Entry)
                    new_cache_entry.album_idx = album_idx
                    new_cache_entry.texture = texture
                    new_cache_entry.frame = app_state.current_frame_rendered

                    app_state.album_art_cache.entries[idx] = new_cache_entry
                    app_state.album_art_cache.count += 1
                    album.cover_art_cache_entry_idx = i32(idx)
                }
            }
        }
    }

    clear(&app_state.album_art_load_queue)
}

@private
invalidate_cache :: proc(app_state: ^App_State) {
    max_frame_diff : u64 = 1000

    entries_to_remove: [dynamic]i32
    defer delete(entries_to_remove)

    for entry, entry_idx in app_state.album_art_cache.entries {
        if entry == nil do continue

        // entry has not been accessed for the last 1000 frames
        // remove from cache
        if app_state.current_frame_rendered - entry.frame > max_frame_diff {
            append(&entries_to_remove, i32(entry_idx))
        }
    }

    for entry_idx_to_remove in entries_to_remove {
        cache_entry := app_state.album_art_cache.entries[entry_idx_to_remove]
        if cache_entry == nil do continue

        album := &app_state.albums[cache_entry.album_idx]
        if album == nil do continue

        remove_entry_from_cache(&app_state.album_art_cache, entry_idx_to_remove)
        album.cover_art_cache_entry_idx = -1
    }

    /*fmt.println("---start---")
    for foo in app_state.album_art_cache.entries {
        if foo != nil {
            fmt.printfln("album Idx: %i; entry_frame: %i; current frame: %i", foo.album_idx, foo.frame, app_state.current_frame_rendered)
        }
    }
    fmt.println("\n---end---")*/
}

@(private = "file")
remove_entry_from_cache :: proc(cache: ^Album_Art_Cache, entry_idx: i32) {
    entry := cache.entries[entry_idx]
    if entry == nil do return

    rl.UnloadTexture(entry.texture)
    cache.entries[entry_idx] = nil
    cache.count -= 1

    assert(cache.count >= 0)
}

@(private = "file")
init_playlists_from_playlist_files :: proc(app_state: ^App_State) {
    playlist_files, err := os.read_directory_by_path(app_state.playlist_path, 0, context.allocator)
    if err != nil {
        fmt.eprintln(#procedure, "Failed to read the playlist directory by path: ", err)
        return
    }
    defer delete(playlist_files)

    for f in playlist_files {
        file_data, err := os.read_entire_file_from_path(f.fullpath, context.allocator)
        if err != nil {
            fmt.eprintln(#procedure, "Failed to read the playlist file: ", err)
            continue
        }
        defer delete(file_data)

        if len(file_data) == 0 do continue

        current_playlist := Playlist{
            playlist_file_path = f.fullpath
        }

        line_idx := 0
        it := string(file_data)
        for line in strings.split_lines_iterator(&it) {
            if line_idx == 0 {
                current_playlist.title = line
            } else {
                track_full_path, err := filepath.join({app_state.library_path, line}, context.allocator)
                if err != nil {
                    fmt.eprintln(#procedure, "Failed to join library path with the path from playlist file: ", err)
                    line_idx += 1
                    continue
                }
                defer delete(track_full_path)

                for &track in app_state.tracks {
                    if strings.compare(string(track.file_path), track_full_path) == 0 {
                        append(&current_playlist.tracks, &track)
                        break
                    }
                }
            }
            line_idx += 1
        }

        append(&app_state.playlists, current_playlist)
    }
}

create_playlist :: proc(app_state: ^App_State, playlist_name: string) {
    err := get_or_create_playlist_dir(app_state.playlist_path)
    if err != nil {
        fmt.eprintln("Could not create or read playlist path: ", err)
        return
    }

    files, dir_read_err := os.read_directory_by_path(app_state.playlist_path, 0, context.allocator)
    if dir_read_err != nil {
        fmt.eprintln(#procedure, "Could not create the playlist: ", dir_read_err)
        return
    }
    defer delete(files)

    next_file_name : string = "mppl0"
    if len(files) > 0 {
        sort.quick_sort_proc(files, proc(a, b: os.File_Info) -> int {
            if a.name < b.name do return -1
            if a.name > b.name do return 1
            return 0
        })

        current_file_name := files[len(files) - 1].name
        current_playlist_nr := current_file_name[len("mppl"):]

        // @todo: if unable to parse, get the second last file and so on
        current_playlist_nr_int, ok := strconv.parse_int(current_playlist_nr)
        assert(ok == true)

        next_file_name = fmt.tprintf("mppl%i", current_playlist_nr_int + 1)
    }

    // @todo: handle error
    file_path, e := filepath.join({app_state.playlist_path, next_file_name}, context.allocator)
    defer delete(file_path)

    playlist_file, file_create_err := os.create(file_path)
    if file_create_err != nil {
        fmt.eprintln(#procedure, "Could not create a playlist file: ", file_create_err)
        return
    }
    defer os.close(playlist_file)

    formatted_playlist_name := fmt.tprintf("%s\n", playlist_name)
    _, err = os.write(playlist_file, transmute([]byte)formatted_playlist_name)
    if err != nil {
        fmt.eprintln(#procedure, "Could not write to the playlist file: ", err)
        return
    }

    new_playlist := Playlist{
        title = playlist_name,
        playlist_file_path = file_path
    }

    append(&app_state.playlists, new_playlist)
}

add_track_to_playlist :: proc(playlist: ^Playlist, track: ^Track, root_dir: string) {
    playlist_file, err := os.open(playlist.playlist_file_path, {.Append, .Write})
    if err != nil {
        fmt.eprintln(#procedure, "Could not open the playlist file: ", err)
        return
    }
    defer os.close(playlist_file)

    relative_track_file_path := fmt.tprintf("%s\n", string(track.file_path)[len(root_dir):])
    _, err = os.write(playlist_file, transmute([]byte)relative_track_file_path)
    if err != nil {
        fmt.eprintln(#procedure, "Failed to write to playlist file", err)
        return
    }

    append(&playlist.tracks, track)
}

delete_playlist :: proc(app_state: ^App_State, playlist: Playlist) {
    // @todo
}


remove_track_from_playlist :: proc(playlist: ^Playlist, track_to_remove: Track) {
    // @todo
}

@require_results
get_or_create_playlist_dir :: proc(path: string) -> os.Error {
    file_info, file_info_err := os.stat(path, context.allocator)
    if file_info_err != nil || file_info.type != .Directory {
        err := os.mkdir(path)
        if err != nil {
            os.file_info_delete(file_info, context.allocator)
            return err
        }
    }

    os.file_info_delete(file_info, context.allocator)
    return nil
}

