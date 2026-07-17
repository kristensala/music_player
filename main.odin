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

FONT_DATA :: #load("res/IBMPlexMono-Regular.ttf")
ALBUM_ART_PLACEHOLDER :: #load("./res/album_placeholder.png")
PLAY_IMG_DATA :: #load("./res/play.png")
PAUSE_IMG_DATA :: #load("./res/pause.png")
NEXT_IMG_DATA :: #load("./res/next.png")
PREVIOUS_IMG_DATA :: #load("./res/previous.png")

COVER_SIZE                 :: 200
SCROLL_INCREMENT           :: 5 // five rows
BOTTOM_BAR_PADDING         :: 50
FONT_18                    :: 18
FONT_20                    :: 20
FONT_30                    :: 30
PLAYBACK_BUTTON_SIZE       :: 30
SIDE_PANEL_ROW_HEIGHT      :: 35
ROW_HEIGHT                 :: 40
TRACK_LIST_OFFSET_X        :: 250
CACHE_MAX_CAPACITY         :: 15

ALL_ARTISTS_OPTION         :: "All Artists"

Track_Idx :: i32
Album_Idx :: i32
Album_Title :: cstring

Row :: struct {
    is_album_row    : bool, // if true then track is nil
    album_idx       : i32,
    track           : ^Track,
    track_idx       : Track_Idx,
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
    rebuild_rows: bool,
    content_max_height: i32, // in pixels
}

Playback_Controls_Panel :: struct {
    playback_controls_panel_rect: rl.Rectangle,

    play_button_texture: rl.Texture2D,
    pause_button_texture: rl.Texture2D,
    next_button_texture: rl.Texture2D,
    previous_button_texture: rl.Texture2D
}

Create_Playlist_Modal :: struct {
    create_playlist_modal_rect: rl.Rectangle,
    create_playlist_modal_input: [dynamic]rune,

    is_create_playlist_modal_open: bool
}

Active_Viewport :: enum i32 {
    Main = 0,
    Create_Playlist_Modal = 1
}

// @todo: should App_State have it's own allocator?
App_State :: struct {
    active_viewport: Active_Viewport,

    using main_panel: Main_Panel,
    using side_panel: Side_Panel,
    using playback_controls_panel: Playback_Controls_Panel,
    using create_playlist_modal: Create_Playlist_Modal,

    fonts: map[i32]rl.Font,

    library_path: string,
    is_library_path_set: bool,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,

    playlist_path: string,
    playlists: [dynamic]Playlist,

    queue: [dynamic]Track_Idx, // @todo: not implemented
    current_position_in_queue: i32,

    default_album_cover_texture: rl.Texture2D,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing_track: ^Track,
    currently_playing_track_idx: i32, // -1 means nothing is playing

    // filtering
    artist_list: [dynamic]cstring,
    current_selected_artist: cstring, // nil means show all the tracks

    album_art_cache: Album_Art_Cache,
    album_art_load_queue: [dynamic]i32, // ref album idx

    current_frame_rendered: u64, // current rendered frame

    show_debug_panel: bool
}

Album_Art_Cache :: struct {
    entries  : [CACHE_MAX_CAPACITY]^Album_Art_Cache_Entry,
    count    : i32,
}

Album_Art_Cache_Entry :: struct {
    texture      : rl.Texture2D,
    album_idx    : i32,

    frame        : u64 // last frame it was rendered
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
    app_state.active_viewport = .Main
    app_state.rebuild_rows = true
    app_state.is_library_path_set = false
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.selected_side_panel_option = .Artist_List // @todo: All_Music once implemented

    load_assets(app_state)
    load_config(app_state)

    /*playlist_path, err := filepath.join({app_state.library_path, ".mppl"}, context.allocator)
    assert(err == nil)
    app_state.playlist_path = playlist_path*/

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
        //walk_music_dir(app_state, app_state.library_path)
        init_library(app_state)
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
        //init_playlists_from_playlist_files(app_state)
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

            if app_state.is_create_playlist_modal_open {
                draw_create_playlist_modal(app_state)
            }
        } else {
            draw_insert_library_path_screen(app_state)
        }

        if app_state.show_debug_panel {
            draw_debug_panel(app_state)
        }

        rl.EndDrawing()
    }

    free_all(context.temp_allocator)

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

    if app_state.rebuild_rows {
        build_rows(app_state)
    }

    if ma.sound_at_end(app_state.ma_sound) {
        handle_next_song_pick_v2(app_state)
    }

    if app_state.is_create_playlist_modal_open {
        app_state.active_viewport = .Create_Playlist_Modal
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
    //delete(app_state.playlist_path)
    delete(app_state.create_playlist_modal_input)
    delete(app_state.queue)

    free(app_state)
}

@(private = "file")
load_assets :: proc(app_state: ^App_State) {
    // fonts
    {
        font_18 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), 18, nil, 0)
        font_20 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), 20, nil, 0)
        font_30 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), 30, nil, 0)

        fonts := make(map[i32]rl.Font)
        fonts[FONT_18] = font_18
        fonts[FONT_20] = font_20
        fonts[FONT_30] = font_30

        app_state.fonts = fonts
    }

    // album art placeholder
    {
        album_placeholder_img := rl.LoadImageFromMemory(".png", raw_data(ALBUM_ART_PLACEHOLDER), i32(len(ALBUM_ART_PLACEHOLDER)))
        rl.ImageResize(&album_placeholder_img, 200, 200)
        app_state.default_album_cover_texture = rl.LoadTextureFromImage(album_placeholder_img)
        rl.UnloadImage(album_placeholder_img)
    }

    // Load play button image
    {
        play_btn_img := rl.LoadImageFromMemory(".png", raw_data(PLAY_IMG_DATA), i32(len(PLAY_IMG_DATA)))
        rl.ImageResize(&play_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.play_button_texture =  rl.LoadTextureFromImage(play_btn_img)
        rl.UnloadImage(play_btn_img)
    }

    // Load pause button image
    {
        pause_btn_img := rl.LoadImageFromMemory(".png", raw_data(PAUSE_IMG_DATA), i32(len(PAUSE_IMG_DATA)))
        rl.ImageResize(&pause_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.pause_button_texture =  rl.LoadTextureFromImage(pause_btn_img)
        rl.UnloadImage(pause_btn_img)
    }

    // Load next button image
    {
        next_btn_img := rl.LoadImageFromMemory(".png", raw_data(NEXT_IMG_DATA), i32(len(NEXT_IMG_DATA)))
        rl.ImageResize(&next_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.next_button_texture =  rl.LoadTextureFromImage(next_btn_img)
        rl.UnloadImage(next_btn_img)
    }

    // Load previous button image
    {
        prev_btn_img := rl.LoadImageFromMemory(".png", raw_data(PREVIOUS_IMG_DATA), i32(len(PREVIOUS_IMG_DATA)))
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

    config_path, config_path_join_err := filepath.join({home_dir, ".config", "music_player"}, context.allocator)
    if config_path_join_err != nil {
        // @todo: handle error
        return
    }
    defer delete(config_path)

    config_file_path, config_file_path_join_err := filepath.join({config_path, "config"}, context.allocator)
    if config_file_path_join_err != nil {
        // @todo: handle err
        return
    }
    defer delete(config_file_path)

    // @todo: handle error. if not exist create else return
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
    switch app_state.active_viewport {
    case .Main:
        handle_main_view_keyboard_events(app_state)
    case .Create_Playlist_Modal:
        handle_create_playlist_modal_keyboard_events(app_state)
    }
}

handle_main_view_keyboard_events :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Main)

    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
        if app_state.ma_sound == nil {
            return
        }

        handle_play_pause(app_state)
    }

    if rl.IsKeyPressed(rl.KeyboardKey.D) {
        app_state.show_debug_panel = !app_state.show_debug_panel
    }
}

// @todo
handle_create_playlist_modal_keyboard_events :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Create_Playlist_Modal)

    input := rl.GetCharPressed()
    if input > 0 {
        append(&app_state.create_playlist_modal_input, input)
    }

    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
        clear(&app_state.create_playlist_modal_input)

        app_state.is_create_playlist_modal_open = false
        app_state.active_viewport = .Main

    }

    if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
        // @todo: create the playlist
        // do not allow empty input or duplicate playlist names

        /*clear(&app_state.create_playlist_modal_input)
        app_state.is_create_playlist_modal_open = false
        app_state.active_viewport = .Main*/
    }

}

// @todo: what if different artists have the same album name
// example: chill bump - ego trip and Papa roach - ego trip
init_library :: proc(app_state: ^App_State) {
    album_map := make(map[Album_Title]Album_Idx)
    defer delete(album_map)

    walk_music_dir_v2(app_state, app_state.library_path, &album_map)
}

walk_music_dir_v2 :: proc(app_state: ^App_State, current_working_dir: string, album_map: ^map[Album_Title]Album_Idx) {
    data, err := os.read_directory_by_path(current_working_dir, 0, context.allocator)
    if err != nil {
        fmt.printf("Could not read the dir", err)
        return
    }
    defer delete(data)

    // @todo: ignore case
    sort.quick_sort_proc(data, proc(a, b: os.File_Info) -> int {
        if a.name < b.name do return -1
        if a.name > b.name do return 1
        return 0
    })

    current_album : ^Album
    found_album_art_path : cstring

    for d in data {
        if d.type == .Directory {
            walk_music_dir_v2(app_state, d.fullpath, album_map)
        } else if d.type == .Regular {
            if filepath.ext(d.fullpath) == ".mp3" || filepath.ext(d.fullpath) == ".flac" || filepath.ext(d.fullpath) == ".wav" {
                // @todo: handle error
                tag, tl_error := tl.get_tag(d.fullpath)

                track := Track{
                    title = strings.clone_to_cstring(tag.title),
                    artist = strings.clone_to_cstring(tag.artist),
                    album_title = strings.clone_to_cstring(tag.album),
                    file_name = strings.clone_to_cstring(d.name),
                    file_path = strings.clone_to_cstring(d.fullpath)
                }

                // create album
                {
                    album_identifier := fmt.ctprintf("%s-%s", current_working_dir, track.album_title)
                    idx, album_exists := album_map[album_identifier]
                    if !album_exists {
                        idx = i32(len(app_state.albums))

                        album := Album{
                            title = track.album_title,
                            artist = track.artist,
                            cover_art_path = found_album_art_path,
                            cover_art_cache_entry_idx = -1
                        }
                        
                        append(&app_state.albums, album)
                        album_map[album_identifier] = idx
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
                found_album_art_path = strings.clone_to_cstring(d.fullpath)
                if current_album != nil {
                    current_album.cover_art_path = found_album_art_path
                }
            }
        }
    }

    // @todo: ignore case
    sort.quick_sort(app_state.artist_list[1:])
}

// @bug: currently assumes that your folder structure is correct, meaning that albums are folder based.
// Should read albums based on tag data.
// Also if it finds an image as the first file then the current album does not exist and the album does not get the cover art
@(private = "file")
walk_music_dir :: proc(app_state: ^App_State, path: string) {
    data, err := os.read_directory_by_path(path, 0, context.allocator)
    if err != nil {
        fmt.printf("Could not read the dir", err)
        return
    }
    defer delete(data)

    // @todo: ignore case
    sort.quick_sort_proc(data, proc(a, b: os.File_Info) -> int {
        if a.name < b.name do return -1
        if a.name > b.name do return 1
        return 0
    })

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
                // @todo
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
    assert(app_state.rebuild_rows == true)
    app_state.rebuild_rows = false

    content_height : i32 = 0

    clear(&app_state.rows)
    for &album, album_idx in app_state.albums {
        if app_state.current_selected_artist != nil {
            if album.artist != app_state.current_selected_artist do continue
        }

        album_title_row := new(Row)
        album_title_row.is_album_row = true
        album_title_row.album_idx = i32(album_idx)
        album_title_row.track_idx = -1

        append(&app_state.rows, album_title_row)

        content_height += ROW_HEIGHT

        album_content_height : i32 = 0
        for track_idx in album.track_indices {
            track := &app_state.tracks[track_idx]
            assert(track != nil)

            track_row := new(Row)
            track_row.track = track
            track_row.track_idx = track_idx

            append(&app_state.rows, track_row)

            //content_height = pos_y + ROW_HEIGHT
            album_content_height += ROW_HEIGHT
        }

        if album_content_height < COVER_SIZE {
            diff := (COVER_SIZE - album_content_height) / ROW_HEIGHT
            for i in 0..<diff {
                append(&app_state.rows, nil)
                album_content_height += ROW_HEIGHT
            }
        }

        content_height += album_content_height // padding after the album
    }

    app_state.content_max_height = content_height

    assert(app_state.rebuild_rows == false)
}

build_queue :: proc(app_state: ^App_State) {
    clear(&app_state.queue)
    app_state.current_position_in_queue = 0

    assert(app_state.currently_playing_track_idx != -1)

    for album, album_idx in app_state.albums[app_state.currently_playing_track.album_idx:] {
        if album.artist != app_state.current_selected_artist && app_state.current_selected_artist != nil do break

        found_current_track := false
        is_current_album := i32(album_idx) == 0

        for track_idx in album.track_indices {
            if !is_current_album {
                append(&app_state.queue, track_idx)
                continue
            }

            if track_idx == app_state.currently_playing_track_idx {
                found_current_track = true
                append(&app_state.queue, track_idx)
                continue
            }

            if found_current_track {
                append(&app_state.queue, track_idx)
            }
        }
    }
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

        if len(album.cover_art_path) > 0 {
            // cache is full
            if app_state.album_art_cache.count >= CACHE_MAX_CAPACITY {
                cache_entry_idx, least_used_cache_entry := least_used_cover_art_idx(app_state)

                cache_entry_album := &app_state.albums[least_used_cache_entry.album_idx]
                cache_entry_album.cover_art_cache_entry_idx = -1

                rl.UnloadTexture(least_used_cache_entry.texture)

                app_state.album_art_cache.entries[cache_entry_idx] = nil
                app_state.album_art_cache.count -= 1
                free(least_used_cache_entry)

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
}

@(private = "file")
remove_entry_from_cache :: proc(cache: ^Album_Art_Cache, entry_idx: i32) {
    entry := cache.entries[entry_idx]
    if entry == nil do return

    rl.UnloadTexture(entry.texture)
    free(entry)
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

