#+feature dynamic-literals
package main

import "core:unicode/utf16"
import "core:fmt"
import "core:math/rand"
import "core:log"
import "core:strings"
import "core:slice"
import "core:sort"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:mem"
import "core:path/filepath"
import "core:os"
import "core:sync"
import "core:thread"
import tl "taglib"
import "nfd"
import "notify"
import "sdbus"

FONT_DATA :: #load("assets/Inter.ttf")
ALBUM_ART_PLACEHOLDER :: #load("./assets/album_placeholder.png")
PLAY_IMG_DATA :: #load("./assets/play-white.png")
PAUSE_IMG_DATA :: #load("./assets/pause-white.png")
REPEAT_IMG_DATA :: #load("./assets/repeat-white.png")
REPEAT_ONE_IMG_DATA :: #load("./assets/repeat-one.png")
REPEAT_QUEUE_IMG_DATA :: #load("./assets/repeat-queue.png")
NEXT_IMG_DATA :: #load("./assets/forward-white.png")
PREVIOUS_IMG_DATA :: #load("./assets/backward-white.png")
SHUFFLE_IMG_DATA :: #load("./assets/shuffle-solid.png")
SHUFFLE_ON_IMG_DATA :: #load("./assets/shuffle-on.png")
SEARCH_IMG_DATA :: #load("./assets/search.png")

FONT_20                    :: 20
FONT_30                    :: 30

CACHE_MAX_CAPACITY         :: 15
ALL_ARTISTS_OPTION         :: "All Artists"
CONFIG_LIBRARY_PATH_PREFIX : string = "LIBRARY_PATH="
EMPTY_IDX :: -1

Track_Idx :: i32
Album_Idx :: i32
Album_Title :: cstring

Row :: struct {
    is_dummy_row        : bool,
    is_album_title_row  : bool, // if true then track is nil
    album_idx           : i32,
    track               : ^Track,
    pos_y               : i32 // @todo
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
    main_panel_scroll_bar_rect: rl.Rectangle,

    main_panel_rect: rl.Rectangle,
    main_panel_scroll_offset: f32,

    rows: [dynamic]^Row,
    rebuild_rows: bool,
    content_max_height: i32, // in pixels
}

Playback_Controls_Panel :: struct {
    playback_controls_panel_rect: rl.Rectangle,

    play_button_texture: rl.Texture2D,
    pause_button_texture: rl.Texture2D,
    next_button_texture: rl.Texture2D,
    previous_button_texture: rl.Texture2D,

    repeat_button_texture: rl.Texture2D,
    repeat_one_button_texture: rl.Texture2D,
    repeat_queue_button_texture: rl.Texture2D,
    shuffle_off_button_texture: rl.Texture2D,
    shuffle_on_button_texture: rl.Texture2D,
    search_logo_texture: rl.Texture2D
}

Caret :: struct {
    rect: rl.Rectangle,
    pos: [2]f32,

    col_idx: i32 // position in input
}

Search_Result_Type :: enum {
    Album,
    Track,
    Artist,
    Command
}

Search_Result_Row :: struct {
    type: Search_Result_Type,

    artist_name: cstring,
    track_idx: Track_Idx, // @note: should probably use a pointer ^Track
    album: ^Album,
    cmd: Command,

    weight: f64
}

Active_Viewport :: enum i32 {
    Main                  = 0,
    Create_Playlist_Modal = 1,
    Search                = 2
}

Playback_Mode :: enum i32 {
    Normal       = 0,
    Repeat_One   = 1,
    Repeat_Queue = 2,
}

Command :: enum {
    Set_Library,
    Create_Playlist
}

COMMANDS := map[Command]cstring{
    .Set_Library = "Change library path",
    .Create_Playlist = "Create a new playlist"
}

App_State :: struct {
    bus: sdbus.Bus,
    last_notification_id: u32,
    trigger_notification: bool,

    mutex: sync.Mutex,
    scanning: bool,

    active_viewport: Active_Viewport,
    playback_mode: Playback_Mode,
    is_shuffle_play: bool,

    using main_panel              : Main_Panel,
    using side_panel              : Side_Panel,
    using playback_controls_panel : Playback_Controls_Panel,
    using create_playlist_modal   : Create_Playlist_Modal,
    using command_palette            : Command_Palette,

    fonts: map[i32]rl.Font,

    config_path         : cstring,
    library_path        : cstring,
    is_library_path_set : bool,
    rescan_library      : bool,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,

    playlist_path : string,
    playlists     : [dynamic]Playlist,

    queue                     : [dynamic]^Track,
    current_position_in_queue : i32,
    rebuild_queue             : bool,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: Audio_State,
    currently_playing_track: ^Track,

    // filtering
    artist_list: [dynamic]cstring,
    current_selected_artist: cstring, // nil means show all the tracks

    // @todo: not implemented
    // ALSO: remove highlight after user interacts with the application in any way
    highlighted_track_after_search: ^Track,

    album_art_cache: Album_Art_Cache,
    album_art_load_queue: [dynamic]Album_Idx, // ref album idx
    default_album_cover_texture: rl.Texture2D,

    current_frame_rendered: u64, // current rendered frame

    show_debug_panel: bool,
}

Album_Art_Cache :: struct {
    entries  : [CACHE_MAX_CAPACITY]^Album_Art_Cache_Entry,
    count    : i32, // cache count
}

Album_Art_Cache_Entry :: struct {
    texture      : rl.Texture2D,
    album_idx    : i32,
    frame        : u64 // last frame it was rendered
}

Audio_State :: enum i32 {
    Stopped = 0,
    Playing = 1,
    Paused = 2
}

Track :: struct {
    title: cstring,
    artist: cstring,
    album_artist: cstring,
    album_title: cstring,
    album_idx: i32,
    file_path: cstring,
    file_name: cstring,
}

Album :: struct {
    title: cstring,
    artist: cstring,

    cover_art_path: cstring,
    cover_art_cache_entry_idx: i32,

    tracks: [dynamic]^Track,
}

Side_Panel_Option :: enum i32 {
    Artist_List = 0,
    Playlists = 1,
    All_Music = 2 // @todo: remove all artists option from artist list and add it to the side_panel options instead. As "All Music"
}

@require_results
@(private = "file")
init_state :: proc() -> ^App_State {
    app_state := new(App_State)
    app_state.active_viewport = .Main
    app_state.playback_mode = .Normal
    app_state.rebuild_queue = false
    app_state.is_library_path_set = false
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.selected_side_panel_option = .Artist_List // @todo: All_Music once implemented
    app_state.rebuild_rows = true

    load_assets(app_state)
    if !load_config(app_state) do panic("Failed to load config")


    /*playlist_path, err := filepath.join({app_state.library_path, ".mppl"}, context.allocator)
    assert(err == nil)
    app_state.playlist_path = playlist_path*/

    app_state.side_panel_rect = rl.Rectangle{0, 0, 350, 0}

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

    app_state.main_panel_rect = rl.Rectangle{
        x = app_state.side_panel_rect.width + MAIN_PANEL_PADDING_LEFT,
        y = MAIN_PANEL_PADDING_TOP
    }

    app_state.playback_controls_panel_rect = rl.Rectangle{ x = 0, height = 170 }

    when ODIN_OS == .Linux {
        app_state.bus = dbus_init()
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

    log_dir, err := os.user_log_dir(context.temp_allocator)
    assert(err == nil)

    log_path, _ := filepath.join({log_dir, "music_player_log.txt"}, context.temp_allocator)
    logh, logh_err := os.open(log_path, {.Create, .Trunc, .Read, .Write })

    if logh_err == os.ERROR_NONE {
        os.stdout = logh
        os.stderr = logh
    }

    logger := logh_err == os.ERROR_NONE ? log.create_file_logger(logh) : log.create_console_logger()
    context.logger = logger

    defer {
        if logh_err == os.ERROR_NONE {
            log.destroy_file_logger(logger)
        } else {
            log.destroy_console_logger(logger)
        }
    }

    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1800, 1250, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    nfd.Init()
    defer nfd.Quit()

    app_state := init_state()

    /*if app_state.is_library_path_set {
        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        init_library(app_state)
        build_rows(app_state) // for ui
        build_queue(app_state)
    }*/
    scanner := thread.create_and_start_with_poly_data(app_state, worker)

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
        log.errorf("Could not init Mini audio engine: %v", engine_init_result)
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

        update_main(app_state)
        update_layout(app_state)

        rl.BeginDrawing()

        rl.ClearBackground(BACKGROUND_COLOR)

        draw_main(app_state)

        if app_state.is_create_playlist_modal_open {
            draw_create_playlist_modal(app_state)
        }

        if app_state.active_viewport == .Search {
            draw_command_palette(app_state)
        }

        if app_state.show_debug_panel {
            draw_debug_panel(app_state)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    thread.destroy(scanner)

    // cleanup
    {
        destroy_state(app_state)
    }
}

worker :: proc(app_state: ^App_State) {
    sync.mutex_lock(&app_state.mutex)
    app_state.scanning = true
    sync.mutex_unlock(&app_state.mutex)

    if app_state.is_library_path_set {
        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        init_library(app_state)
        build_rows(app_state) // for ui
        build_queue(app_state)
    }

    sync.mutex_lock(&app_state.mutex)
    app_state.scanning = false
    sync.mutex_unlock(&app_state.mutex)
}

@(private = "file")
update_main :: proc(app_state: ^App_State) {
    app_state.current_frame_rendered += 1

    invalidate_cache(app_state)
    process_album_art_queue(app_state)
    handle_keyboard_events(app_state)

    if app_state.trigger_notification {
        trigger_notification(app_state)
    }

    if app_state.rebuild_rows {
        build_rows(app_state)
    }

    if app_state.rescan_library {
        app_state.rescan_library = false

        clear_cache(&app_state.album_art_cache)
        reset_playback(app_state)
        reset_library(app_state)

        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        init_library(app_state)

        build_rows(app_state) // for ui
        build_queue(app_state)
    }

    if ma.sound_at_end(app_state.ma_sound) {
        if app_state.playback_mode == .Normal || app_state.playback_mode == .Repeat_Queue {
            handle_next_track_pick(app_state)
        } else if app_state.playback_mode == .Repeat_One {
            player_repeat_one(app_state)
        }
    }

    if app_state.rebuild_queue {
        build_queue(app_state)
        find_and_set_current_position_in_queue(app_state)
        app_state.rebuild_queue = false
    }

    if app_state.is_create_playlist_modal_open {
        app_state.active_viewport = .Create_Playlist_Modal
    }
}

player_repeat_one :: proc(app_state: ^App_State) {
    res := ma.sound_seek_to_pcm_frame(app_state.ma_sound, 0)
    if res != .SUCCESS {
        log.errorf("Could not seek sound to 0 pcm frame: %v", res)
        reset_playback(app_state)
        return
    }

    sound_start_result := ma.sound_start(app_state.ma_sound)
    if sound_start_result != .SUCCESS {
        log.errorf("Failed to start the sound: %v", sound_start_result)
        reset_playback(app_state)
        return
    }
}

@(private = "file")
reset_library :: proc(app_state: ^App_State) {
    ma.sound_uninit(app_state.ma_sound)
    clear(&app_state.rows)
    clear(&app_state.artist_list)

    for entry in app_state.album_art_cache.entries {
        if entry == nil do continue
        rl.UnloadTexture(entry.texture)
    }

    for a in app_state.albums {
        delete(a.tracks)
        delete(a.cover_art_path)
    }
    clear(&app_state.albums)

    for t in app_state.tracks {
        delete(t.file_name)
        delete(t.file_path)
        delete(t.title)
        delete(t.artist)
        delete(t.album_artist)
        delete(t.album_title)
    }
    clear(&app_state.tracks)
    clear(&app_state.queue)
}

// Sets the player into a Stopped state
reset_playback :: proc(app_state: ^App_State) {
    if app_state.ma_sound != nil {
        ma.sound_uninit(app_state.ma_sound)
    }

    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.currently_playing_track = nil
}

@(private = "file")
destroy_state :: proc(app_state: ^App_State) {
    sdbus.flush_close_unref(app_state.bus)

    ma.sound_uninit(app_state.ma_sound)

    delete(app_state.rows)
    delete(app_state.artist_list)

    for entry in app_state.album_art_cache.entries {
        if entry == nil do continue
        rl.UnloadTexture(entry.texture)
    }

    for a in app_state.albums {
        delete(a.tracks)
        delete(a.cover_art_path)
    }
    delete(app_state.albums)

    for t in app_state.tracks {
        delete(t.file_name)
        delete(t.file_path)
        delete(t.title)
        delete(t.artist)
        delete(t.album_artist)
        delete(t.album_title)
    }
    delete(app_state.tracks)

    rl.UnloadTexture(app_state.default_album_cover_texture)
    rl.UnloadTexture(app_state.play_button_texture)
    rl.UnloadTexture(app_state.pause_button_texture)
    rl.UnloadTexture(app_state.next_button_texture)
    rl.UnloadTexture(app_state.previous_button_texture)
    rl.UnloadTexture(app_state.repeat_button_texture)
    rl.UnloadTexture(app_state.repeat_one_button_texture)
    rl.UnloadTexture(app_state.repeat_queue_button_texture)
    rl.UnloadTexture(app_state.shuffle_on_button_texture)
    rl.UnloadTexture(app_state.shuffle_off_button_texture)
    rl.UnloadTexture(app_state.search_logo_texture)

    for key, value in app_state.fonts {
        rl.UnloadFont(value)
    }
    delete(app_state.fonts)

    // @note: if set through file dialog then no need to delete. If read from config file, I think I should delete
    delete(app_state.library_path)

    //delete(app_state.playlist_path)
    delete(app_state.create_playlist_modal_input)
    delete(app_state.queue)

    delete(app_state.command_palette_input)
    delete(app_state.search_results)
    delete(app_state.config_path)

    free(app_state)
}

@(private = "file")
load_assets :: proc(app_state: ^App_State) {
    // fonts
    {
        font_20 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), FONT_20, nil, 0)
        font_30 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), FONT_30, nil, 0)

        fonts := make(map[i32]rl.Font)
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
        app_state.play_button_texture = rl.LoadTextureFromImage(play_btn_img)
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

    // Repeat button img
    {
        repeat_btn_img := rl.LoadImageFromMemory(".png", raw_data(REPEAT_IMG_DATA), i32(len(REPEAT_IMG_DATA)))
        rl.ImageResize(&repeat_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.repeat_button_texture =  rl.LoadTextureFromImage(repeat_btn_img)
        rl.UnloadImage(repeat_btn_img)
    }

    // Repeat one button img
    {
        repeat_one_btn_img := rl.LoadImageFromMemory(".png", raw_data(REPEAT_ONE_IMG_DATA), i32(len(REPEAT_ONE_IMG_DATA)))
        rl.ImageResize(&repeat_one_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.repeat_one_button_texture =  rl.LoadTextureFromImage(repeat_one_btn_img)
        rl.UnloadImage(repeat_one_btn_img)
    }

    // Repeat queue button img
    {
        repeat_queue_img := rl.LoadImageFromMemory(".png", raw_data(REPEAT_QUEUE_IMG_DATA), i32(len(REPEAT_QUEUE_IMG_DATA)))
        rl.ImageResize(&repeat_queue_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.repeat_queue_button_texture =  rl.LoadTextureFromImage(repeat_queue_img)
        rl.UnloadImage(repeat_queue_img)
    }

    // Shuffle off
    {
        shuffle_queue := rl.LoadImageFromMemory(".png", raw_data(SHUFFLE_IMG_DATA), i32(len(SHUFFLE_IMG_DATA)))
        rl.ImageResize(&shuffle_queue, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.shuffle_off_button_texture =  rl.LoadTextureFromImage(shuffle_queue)
        rl.UnloadImage(shuffle_queue)
    }
    // Shuffle on
    {
        shuffle_queue := rl.LoadImageFromMemory(".png", raw_data(SHUFFLE_ON_IMG_DATA), i32(len(SHUFFLE_ON_IMG_DATA)))
        rl.ImageResize(&shuffle_queue, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.shuffle_on_button_texture =  rl.LoadTextureFromImage(shuffle_queue)
        rl.UnloadImage(shuffle_queue)
    }
    // Search logo
    {
        search_logo := rl.LoadImageFromMemory(".png", raw_data(SEARCH_IMG_DATA), i32(len(SEARCH_IMG_DATA)))
        rl.ImageResize(&search_logo, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.search_logo_texture =  rl.LoadTextureFromImage(search_logo)
        rl.UnloadImage(search_logo)
    }
}

@(private = "file")
create_config_file :: proc(path: string) -> bool {
    config_file, err := os.create(path)
    if err != nil {
        log.errorf("Could not create config file: %v", err)
        return false
    }
    defer os.close(config_file)

    _, err = os.write(config_file, transmute([]byte)CONFIG_LIBRARY_PATH_PREFIX)
    if err != nil {
        log.errorf("Could not write to config file: %v", err)
        return false
    }

    return true
}

@(private = "file")
load_config :: proc(app_state: ^App_State) -> bool {
    home_dir, err := os.user_home_dir(context.allocator)
    if err != nil {
        log.errorf("Failed to get user_home_dir: %v", err)
        return false
    }
    defer delete(home_dir)

    config_path, config_path_join_err := filepath.join({home_dir, ".config", "music_player"}, context.allocator)
    if config_path_join_err != nil {
        log.errorf("filepath.join error for config: %v", config_path_join_err)
        return false
    }
    defer delete(config_path)

    config_file_path, config_file_path_join_err := filepath.join({config_path, "config"}, context.allocator)
    if config_file_path_join_err != nil {
        fmt.eprintln("filepath.join error for config file: ", config_file_path_join_err)
        return false
    }
    defer delete(config_file_path)

    config_path_exists := os.exists(config_path)
    if !config_path_exists {
        mkdir_err := os.mkdir(config_path)
        if mkdir_err != nil {
            log.errorf("Could not create music_player config directory: %v", mkdir_err)
            return false
        }
    }

    if !os.exists(config_file_path) {
        create_result := create_config_file(config_file_path)
        if !create_result do return false
    }

    app_state.config_path = strings.clone_to_cstring(config_file_path)

    file_data, read_err := os.read_entire_file_from_path(config_file_path, context.allocator)
    if read_err != nil {
        log.errorf("Could not read config file: %v", read_err)
        return false
    }
    defer delete(file_data)

    it := string(file_data)
    for line in strings.split_lines_iterator(&it) {
        // process line
        if strings.has_prefix(line, CONFIG_LIBRARY_PATH_PREFIX) {
            library_path := line[len(CONFIG_LIBRARY_PATH_PREFIX):]
            is_valid_library_path := os.exists(library_path)
            if !is_valid_library_path do continue

            if len(library_path) > 0 {
                app_state.library_path = strings.clone_to_cstring(library_path)
                app_state.is_library_path_set = true
            }
        }
    }

    return true
}

init_sound :: proc(ma_engine: ^ma.engine, ma_sound: ^ma.sound, file_path: cstring) -> ma.result {
    // @note: windows can't handle special chars in file name
    when ODIN_OS == .Windows {
        utf8_path := string(file_path)
        wide := make([]u16, len(utf8_path) + 1)
        defer delete(wide)

        written := utf16.encode_string(wide, utf8_path)
        wide[written] = 0
        path_u16: [^]u16 = &wide[0]

        res := ma.sound_init_from_file_w(ma_engine, path_u16, {.STREAM}, nil, nil, ma_sound)
        return res
    } else {
        res := ma.sound_init_from_file(ma_engine, file_path, {.STREAM}, nil, nil, ma_sound)
        return res
    }
}

play_selected_track :: proc(app_state: ^App_State, selected_track: ^Track) -> bool {
    if app_state.ma_sound != nil {
        ma.sound_uninit(app_state.ma_sound)
        app_state.ma_sound = nil
    }

    app_state.ma_sound = new(ma.sound)

    res := init_sound(&app_state.ma_engine, app_state.ma_sound, selected_track.file_path)
    if res != .SUCCESS {
        reset_playback(app_state)

        log.errorf(
            "ma.sound_init_from_file failed: %v. FilePath: %s", 
            res, selected_track.file_path
        )

        return false
    } else {
        sound_start_result := ma.sound_start(app_state.ma_sound)
        if sound_start_result == .SUCCESS {
            app_state.audio_state = .Playing
            app_state.currently_playing_track = selected_track
            app_state.trigger_notification = true
            return true
        } else {
            log.errorf(
                "ma.sound_start failed: %v. FilePath: %s", 
                sound_start_result, selected_track.file_path
            )
            reset_playback(app_state)
            return false
        }
    }
    return false
}

@(private = "file")
init_library :: proc(app_state: ^App_State) {
    scan_library(app_state, string(app_state.library_path))
    create_albums(app_state)

    for a in app_state.albums {
        sort.quick_sort_proc(a.tracks[:], proc(a, b: ^Track) -> int {
            x, err_x := strings.to_lower(string(a.file_name), context.temp_allocator)
            y, err_y := strings.to_lower(string(b.file_name), context.temp_allocator)

            if x < y do return -1
            if x > y do return 1
            return 0
        })
    }
}

@(private = "file")
create_track :: proc(file_name: string, file_path: string) -> (Track, tl.Error) {
    tag, tl_error := tl.get_tag(file_path)
    if tl_error != nil {
        log.errorf("Failed to read %s metadata; Err: %v", file_path, tl_error)
        return {}, tl_error
    }
    defer tl.tag_destroy(&tag)

    title := tag.title
    if len(title) == 0 {
        title = file_name
    }

    track := Track{
        title = strings.clone_to_cstring(title),
        artist = strings.clone_to_cstring(tag.artist),
        album_artist = strings.clone_to_cstring(tag.album_artist),
        album_title = strings.clone_to_cstring(tag.album),
        file_name = strings.clone_to_cstring(file_name),
        file_path = strings.clone_to_cstring(file_path)
    }

    return track, nil
}

@(private = "file")
scan_library :: proc(app_state: ^App_State, current_working_dir: string) {
    data, err := os.read_directory_by_path(current_working_dir, 0, context.allocator)
    if err != nil {
        log.errorf("Could not read the dir: %v; Current working dir: %s", err, current_working_dir)
        return
    }
    defer delete(data)

    sort.quick_sort_proc(data[:], proc(a, b: os.File_Info) -> int {
        x, err_x := strings.to_lower(a.name, context.temp_allocator)
        y, err_y := strings.to_lower(b.name, context.temp_allocator)

        if x < y do return -1
        if x > y do return 1
        return 0
    })

    for d in data {
        if d.type == .Directory {
            scan_library(app_state, d.fullpath)
        } else if d.type == .Regular {
            if filepath.ext(d.fullpath) == ".mp3" || filepath.ext(d.fullpath) == ".flac" || filepath.ext(d.fullpath) == ".wav" {
                track, err := create_track(d.name, d.fullpath)
                if err != nil {
                    log.errorf("Could not create a track; path: %s; Err: %v", d.fullpath, err)
                    continue
                }
                append(&app_state.tracks, track)
            }
        }
    }
}

@(private = "file")
create_albums :: proc(app_state: ^App_State) {
    tmp_album_map : map[string]Album_Idx
    defer delete(tmp_album_map)

    for &it, it_idx in app_state.tracks {
        dir := filepath.dir(string(it.file_path))
        album_identifier := fmt.aprintf("%s_%s", dir, it.album_title, context.temp_allocator)

        album_idx, album_exists := tmp_album_map[album_identifier]
        if !album_exists {
            album_idx = i32(len(app_state.albums))
            album_cover := find_album_cover(dir)

            artist := len(it.album_artist) > 0 ? it.album_artist : it.artist
            album := Album{
                title = it.album_title,
                artist = artist,
                cover_art_path = album_cover,
                cover_art_cache_entry_idx = EMPTY_IDX
            }
            tmp_album_map[album_identifier] = album_idx
            append(&app_state.albums, album)
        }
        
        album := &app_state.albums[album_idx]
        append(&album.tracks, &it)
        it.album_idx = album_idx

        if !slice.contains(app_state.artist_list[:], album.artist) {
            append(&app_state.artist_list, album.artist)
        }
    }

}

@(private = "file")
find_album_cover :: proc(dir: string) -> cstring {
    cover_path, err := filepath.join({dir, "cover.jpg"}, context.temp_allocator)
    if err != nil do panic(fmt.tprintf("Failed to join filepath: ", err))
    if os.exists(cover_path) do return strings.clone_to_cstring(cover_path)

    cover_path, err = filepath.join({dir, "cover.jpeg"}, context.temp_allocator)
    if err != nil do panic(fmt.tprintf("Failed to join filepath: ", err))
    if os.exists(cover_path) do return strings.clone_to_cstring(cover_path)

    cover_path, err = filepath.join({dir, "cover.png"}, context.temp_allocator)
    if err != nil do panic(fmt.tprintf("Failed to join filepath: ", err))
    if os.exists(cover_path) do return strings.clone_to_cstring(cover_path)

    return nil
}

// @todo: set position y of each row here
// so I can draw the rows based on the pre-calculated pos_y
@(private = "file")
build_rows :: proc(app_state: ^App_State) {
    // @todo: do not clear until new rows are built
    clear(&app_state.rows)
    app_state.rebuild_rows = false
    app_state.main_panel_scroll_offset = 0

    pos_y : i32 = MAIN_PANEL_PADDING_TOP
    for &album, album_idx in app_state.albums {
        if app_state.current_selected_artist != nil {
            if album.artist != app_state.current_selected_artist do continue
        }

        album_title_row := new(Row)
        album_title_row.is_album_title_row = true
        album_title_row.album_idx = i32(album_idx)
        album_title_row.pos_y = pos_y
        pos_y += ROW_HEIGHT

        append(&app_state.rows, album_title_row)

        album_content_height : i32 = 0
        for &track in album.tracks {
            assert(track != nil)

            track_row := new(Row)
            track_row.track = track
            track_row.pos_y = pos_y

            pos_y += ROW_HEIGHT

            append(&app_state.rows, track_row)

            //content_height = pos_y + ROW_HEIGHT
            album_content_height += ROW_HEIGHT
        }

        if album_content_height < ALBUM_COVER_SIZE {
            for ;; {
                dummy_row := new(Row)
                dummy_row.is_dummy_row = true
                dummy_row.album_idx = -1
                dummy_row.pos_y = pos_y

                album_content_height += ROW_HEIGHT
                pos_y += ROW_HEIGHT

                append(&app_state.rows, dummy_row)
                if album_content_height >= ALBUM_COVER_SIZE do break
            }
        }

    }

    app_state.content_max_height = pos_y

    assert(app_state.rebuild_rows == false)
}

@(private = "file")
find_and_set_current_position_in_queue :: proc(app_state: ^App_State) {
    assert(len(app_state.queue) > 0)

    if app_state.currently_playing_track == nil do return

    for track, i in app_state.queue {
        if app_state.currently_playing_track.file_path == track.file_path {
            app_state.current_position_in_queue = i32(i)
            break
        }
    }
}

// Initial build has all the tracks in queue,
// unless there is an artist filter, or playlist selected(playlists not done)
@(private = "file")
build_queue :: proc(app_state: ^App_State) {
    clear(&app_state.queue)

    filtered_by_artist := app_state.current_selected_artist != nil
    for album, album_idx in app_state.albums {
        if filtered_by_artist {
            if album.artist == app_state.current_selected_artist {
                append(&app_state.queue, ..album.tracks[:])
            }
        } else {
            append(&app_state.queue, ..album.tracks[:])
        }
    }

    if app_state.is_shuffle_play {
        shuffle_queue(app_state)
    }
}

shuffle_queue :: proc(app_state: ^App_State) {
    if len(app_state.queue) == 0 do return

    for i := len(app_state.queue) - 1; i >= 1; i -= 1 {
        j := rand.int31_max(i32(len(app_state.queue)))

        // currently playing track should be at the beginning of the queue when shuffled
        if app_state.currently_playing_track != nil && app_state.queue[i].file_path == app_state.currently_playing_track.file_path {
            app_state.queue[0], app_state.queue[i] = app_state.queue[i], app_state.queue[0] 
        } else if app_state.currently_playing_track != nil && app_state.queue[j].file_path == app_state.currently_playing_track.file_path {
            app_state.queue[0], app_state.queue[j] = app_state.queue[j], app_state.queue[0]
        } else {
            app_state.queue[i], app_state.queue[j] = app_state.queue[j], app_state.queue[i]
        }
    }

    find_and_set_current_position_in_queue(app_state)
}

@(private = "file")
oldest_cover_art_cache_entry :: proc(app_state: ^App_State) -> (cache_entry_idx: i32, cache_entry: ^Album_Art_Cache_Entry) {
    smallest_frame_count : u64
    entry_idx: i32
    e : ^Album_Art_Cache_Entry

    for entry, idx in app_state.album_art_cache.entries {
        if idx == 0 {
            smallest_frame_count = entry.frame
            entry_idx = i32(idx)
            e = entry
            continue
        }

        if entry.frame < smallest_frame_count {
            smallest_frame_count = entry.frame
            entry_idx = i32(idx)
            e = entry
        }
    }

    return entry_idx, e
}

// Add album cover art into queue
@(private = "file")
request_cover_load :: proc(queue: ^[dynamic]Album_Idx, album_idx: i32) {
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

// Consumes the album art queue
// If cache is full, gets the oldest cache entry and replaces with the one in queue
@(private = "file")
process_album_art_queue :: proc(app_state: ^App_State) {
    for album_idx, idx in app_state.album_art_load_queue {
        album := &app_state.albums[album_idx]

        if len(album.cover_art_path) > 0 {
            // cache is full
            if app_state.album_art_cache.count >= CACHE_MAX_CAPACITY {
                cache_entry_idx, oldest_cache_entry := oldest_cover_art_cache_entry(app_state)

                cache_entry_album := &app_state.albums[oldest_cache_entry.album_idx]
                cache_entry_album.cover_art_cache_entry_idx = EMPTY_IDX

                rl.UnloadTexture(oldest_cache_entry.texture)

                app_state.album_art_cache.entries[cache_entry_idx] = nil
                app_state.album_art_cache.count -= 1
                free(oldest_cache_entry)

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

                idx := EMPTY_IDX
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

// Remove stale cache entries
// If entry has not been accessed in the last 1000 frame, remove it
@(private = "file")
invalidate_cache :: proc(app_state: ^App_State) {
    stale_frame_count : u64 = 1000

    entries_to_remove: [dynamic]i32
    defer delete(entries_to_remove)

    for entry, entry_idx in app_state.album_art_cache.entries {
        if entry == nil do continue

        // entry has not been accessed for the last 1000 frames
        // remove from cache
        if app_state.current_frame_rendered - entry.frame > stale_frame_count {
            append(&entries_to_remove, i32(entry_idx))
        }
    }

    for entry_idx_to_remove in entries_to_remove {
        cache_entry := app_state.album_art_cache.entries[entry_idx_to_remove]
        if cache_entry == nil do continue

        album := &app_state.albums[cache_entry.album_idx]
        if album == nil do continue

        remove_entry_from_cache(&app_state.album_art_cache, entry_idx_to_remove)
        album.cover_art_cache_entry_idx = EMPTY_IDX
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

// Clears Album cover cache entirely
@(private = "file")
clear_cache :: proc(cache: ^Album_Art_Cache) {
    for &e in cache.entries {
        if e == nil do continue
        rl.UnloadTexture(e.texture)
        e = nil
        free(e)
    }
    cache.count = 0
}

// Gets album cover from cache. If no cache hit adds cover to be loaded into a queue
get_album_cover_texture :: proc(app_state: ^App_State, album_idx: Album_Idx) -> (txr: rl.Texture2D, found: bool)  {
    album := app_state.albums[album_idx]
    if album.cover_art_cache_entry_idx >= 0 {
        cache_entry := app_state.album_art_cache.entries[album.cover_art_cache_entry_idx]
        cache_entry.frame = app_state.current_frame_rendered
        return cache_entry.texture, true
    } else {
        if len(album.cover_art_path) > 0 {
            request_cover_load(&app_state.album_art_load_queue, album_idx)
            return {}, false
        } else {
            return app_state.default_album_cover_texture, true
        }
    }
    return app_state.default_album_cover_texture, true
}

// Update layout after window has been drawn or resized
@(private = "file")
update_layout :: proc(app_state: ^App_State) {
    app_state.side_panel_rect.height = app_state.main_panel_rect.height + app_state.main_panel_rect.y // @explain
    app_state.side_panel_option_content_rect.height = app_state.side_panel_rect.height - app_state.side_panel_options_rect.height

    app_state.main_panel_rect.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel_rect.height
    app_state.main_panel_rect.width = f32(rl.GetScreenWidth()) - app_state.side_panel_rect.width - MAIN_PANEL_PADDING_RIGHT - MAIN_PANEL_PADDING_LEFT

    app_state.playback_controls_panel_rect.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel_rect.y = app_state.main_panel_rect.height
}

@(private = "file")
trigger_notification :: proc(app_state: ^App_State) {
    app_state.trigger_notification = false

    if app_state.bus == nil do return
    if app_state.currently_playing_track == nil do return

    when ODIN_OS == .Linux {
        notification_id, err := notify.send_notification(app_state.bus, 
            get_track_album_cover_path(app_state, app_state.currently_playing_track),
            app_state.currently_playing_track.title,
            app_state.currently_playing_track.artist,
            app_state.last_notification_id)

        if err != nil {
            log.errorf("Dbus send notification error: %v; track title: %v", err, app_state.currently_playing_track.title)
            return
        }

        app_state.last_notification_id = notification_id
    } else {
        log.warn("notifications not implemented for OS")
    }
}

@(private = "file")
dbus_init :: proc() -> sdbus.Bus {
    bus: sdbus.Bus
    res := sdbus.open_user(&bus)
    if res < 0 {
        log.errorf("Failed to connect to DBUS: ", res)
        return nil
    }

    return bus
}

