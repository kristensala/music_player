package main

import "core:fmt"
import "core:strings"
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

App_State :: struct {
    using main_panel: Main_Panel,
    using side_panel: Side_Panel,

    fonts: map[i32]rl.Font,
    library_path: string,
    is_library_path_set: bool,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,

    playlist_path: string,
    playlists: [dynamic]Playlist,

    queue: [dynamic]Track_Idx,

    default_album_cover_texture: rl.Texture2D,
    play_button_texture: rl.Texture2D,
    pause_button_texture: rl.Texture2D,
    next_button_texture: rl.Texture2D,
    previous_button_texture: rl.Texture2D,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing_track: ^Track,

    playback_controls_panel: rl.Rectangle,

    // filtering
    artist_list: [dynamic]cstring,
    current_selected_artist: cstring, // nil means show all the tracks

    album_art_cache: Album_Art_Cache,
    album_art_load_queue: [dynamic]i32, // ref album idx

    current_frame_rendered: u64 // current rendered frame
}

Album_Art_Cache :: struct {
    entries: [15]^Album_Art_Cache_Entry,
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
    album: cstring,
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
    app_state.playback_controls_panel = rl.Rectangle{ x = 0, height = 170 }

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
        delete(t.album)
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
        font_16 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_18, nil, 0)
        font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_20, nil, 0)
        font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_30, nil, 0)

        fonts := make(map[i32]rl.Font)
        fonts[FONT_18] = font_16
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
    buf := make([]u8, len(s))
    defer delete(buf)
    copy(buf, s)

    _, err = os.write(config_file, buf)
    if err != nil {
        fmt.eprintln("Could not write to config file")
        return
    }

}

// @todo: windows
@(private = "file")
load_config :: proc(app_state: ^App_State) {
    home_dir, err  := os.user_home_dir(context.allocator)
    config_path, join_err := filepath.join({home_dir, ".config", "music_player"}, context.allocator)
    assert(join_err == nil, "Probably programmer error")
    defer delete(config_path)

    // @todo: handle err
    config_file_path, e := filepath.join({config_path, "config"}, context.allocator)
    assert(e == nil, "Probably programmer error")
    defer delete(config_file_path)

    file_info, file_info_err := os.stat(config_path, context.allocator)
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
                    album = strings.clone_to_cstring(tag.album),
                    file_name = strings.clone_to_cstring(d.name),
                    file_path = strings.clone_to_cstring(d.fullpath)
                }

                // create album
                {
                    idx, album_exists := album_map[track.album]
                    if !album_exists {
                        idx = len(app_state.albums)

                        album := Album{
                            title = track.album,
                            artist = track.artist,
                            cover_art_cache_entry_idx = -1
                        }
                        append(&app_state.albums, album)
                        album_map[track.album] = idx
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
    if len(queue) == 15 do return

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

// @todo: buggy
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

@private
update_layout :: proc(app_state: ^App_State) {
    // -40 := 20px padding from left and right
    app_state.main_panel_rect.width = f32(rl.GetScreenWidth() - 40)
    app_state.main_panel_rect.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel.height
    app_state.side_panel_rect.height = app_state.main_panel_rect.height + app_state.main_panel_rect.y // @explain
    app_state.side_panel_option_content_rect.height = app_state.side_panel_rect.height - app_state.side_panel_options_rect.height

    app_state.playback_controls_panel.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel.y = app_state.main_panel_rect.height
}
