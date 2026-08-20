#+feature dynamic-literals
package main

import "core:fmt"
import "core:math/rand"
import "core:log"
import "core:unicode/utf8"
import "core:strings"
import "core:strconv"
import "core:slice"
import "core:sort"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:mem"
import "core:path/filepath"
import "core:os"
import "core:sync"
import tl "taglib"
import "nfd"
import "sdbus"
import "notify"

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

ALBUM_COVER_SIZE           :: 200
SCROLL_INCREMENT           :: 5 // five rows
BOTTOM_BAR_PADDING         :: 50
FONT_18                    :: 18
FONT_20                    :: 20
FONT_30                    :: 30
PLAYBACK_BUTTON_SIZE       :: 30
SIDE_PANEL_ROW_HEIGHT      :: 30
ROW_HEIGHT                 :: 30
TRACK_LIST_OFFSET_X        :: 250
CACHE_MAX_CAPACITY         :: 15
MAIN_PANEL_PADDING_TOP :: 20
MAIN_PANEL_PADDING_RIGHT :: 20
MAIN_PANEL_PADDING_LEFT :: 20

BACKGROUND_COLOR :: rl.Color{ 0, 21, 36, 255 } // Ink Black
HIGHLIGHT_COLOR :: rl.Color{255, 125, 0, 255 } // Harvest Orange
TEXT_COLOR :: rl.Color{255, 236, 209, 255 } //  Papaya Whip
STORMY_TEAL :: rl.Color{21, 97, 109, 255} // Stormy Teal

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

Playlist :: struct {
    title: string,
    file_name: string, // path is always library_path/.mppl/{file_name}
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
    main_panel_scroll_bar_rect: rl.Rectangle,

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

Search_Panel :: struct {
    caret: Caret,
    search_panel_rect: rl.Rectangle,

    search_input: [dynamic]rune,
    search_results: [dynamic]Search_Result_Row,

    search_panel_scroll_index: i32
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
    cmd: Command
}

Create_Playlist_Modal :: struct {
    create_playlist_modal_rect: rl.Rectangle,
    create_playlist_modal_input: [dynamic]rune,

    is_create_playlist_modal_open: bool
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
    active_viewport: Active_Viewport,
    playback_mode: Playback_Mode,
    is_shuffle_play: bool,

    using main_panel              : Main_Panel,
    using side_panel              : Side_Panel,
    using playback_controls_panel : Playback_Controls_Panel,
    using create_playlist_modal   : Create_Playlist_Modal,
    using search_panel            : Search_Panel,

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

@private
@require_results
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

    if app_state.is_library_path_set {
        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        init_library(app_state)
        build_rows(app_state) // for ui
        build_queue(app_state)
    }

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
            draw_search_panel(app_state)
        }

        if app_state.show_debug_panel {
            draw_debug_panel(app_state)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
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

    if app_state.trigger_notification {
        trigger_notification(app_state)
    }

    if app_state.rebuild_rows {
        build_rows(app_state)
    }

    if app_state.rescan_library {
        app_state.rescan_library = false

        clear_cache(&app_state.album_art_cache)
        reset_player(app_state)
        reset_library(app_state)

        append(&app_state.artist_list, ALL_ARTISTS_OPTION)
        init_library(app_state)

        build_rows(app_state) // for ui
        build_queue(app_state)
    }

    if ma.sound_at_end(app_state.ma_sound) {
        if app_state.playback_mode == .Normal || app_state.playback_mode == .Repeat_Queue {
            result := handle_next_track_pick(app_state)
            if !result {
                reset_player(app_state)
            } else {
                app_state.trigger_notification = true
            }
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
        reset_player(app_state)
        return
    }

    sound_start_result := ma.sound_start(app_state.ma_sound)
    if sound_start_result != .SUCCESS {
        log.errorf("Failed to start the sound: %v", sound_start_result)
        reset_player(app_state)
        return
    }
}

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
reset_player :: proc(app_state: ^App_State) {
    ma.sound_uninit(app_state.ma_sound)
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.currently_playing_track = nil
}

@private
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

    delete(app_state.search_input)
    delete(app_state.search_results)
    delete(app_state.config_path)

    free(app_state)
}

@(private = "file")
load_assets :: proc(app_state: ^App_State) {
    // fonts
    {
        font_18 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), FONT_18, nil, 0)
        font_20 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), FONT_20, nil, 0)
        font_30 := rl.LoadFontFromMemory(".ttf", raw_data(FONT_DATA), i32(len(FONT_DATA)), FONT_30, nil, 0)

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

@private
handle_keyboard_events :: proc(app_state: ^App_State) {
    switch app_state.active_viewport {
    case .Main:
        handle_main_view_keyboard_events(app_state)
    case .Create_Playlist_Modal:
        handle_create_playlist_modal_keyboard_events(app_state)
    case .Search:
        handle_search_panel_keyboard_events(app_state)
    }
}

close_search_panel :: proc(app_state: ^App_State) {
    app_state.active_viewport = .Main
    app_state.search_panel_scroll_index = 0
    app_state.search_panel.caret.col_idx = 0
    app_state.search_panel.caret.pos.x = 0

    clear(&app_state.search_input)
    clear(&app_state.search_results)
}

handle_search_panel_keyboard_events :: proc(app_state: ^App_State) {
    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
        close_search_panel(app_state)
    }

    if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
        app_state.search_panel_scroll_index = 0

        if len(app_state.search_input) > 0 {
            pop(&app_state.search_input)

            // update caret position
            {
                input := utf8.runes_to_string(app_state.search_input[:])
                cinput := strings.clone_to_cstring(input)
                text_measurement := rl.MeasureTextEx(app_state.fonts[FONT_20], cinput, FONT_20, 0)
                delete(cinput)
                delete(input)

                app_state.search_panel.caret.pos.x = text_measurement.x
                app_state.search_panel.caret.col_idx -= 1
            }
        }
        update_search_results(app_state)
    }

    // @todo: ignore case and move cursor and insert at cursor position
    // ability to navigate in results with arrow keys
    input := rl.GetCharPressed()
    if input > 0 {
        app_state.search_panel_scroll_index = 0

        // update caret position
        {
            app_state.search_panel.caret.col_idx += 1
            glyph_info := rl.GetGlyphInfo(app_state.fonts[FONT_20], input)
            app_state.search_panel.caret.pos.x += f32(glyph_info.advanceX)
        }

        append(&app_state.search_input, input)
        if len(app_state.search_input) < 2 do return

        update_search_results(app_state)
    }
}

update_search_results :: proc(app_state: ^App_State) {
    input := utf8.runes_to_string(app_state.search_input[:], context.temp_allocator)

    if len(input) < 2 {
        clear(&app_state.search_results)
        return
    }

    results : [dynamic]Search_Result_Row
    defer delete(results)

    input_lower := strings.to_lower(input, context.temp_allocator)
    if strings.has_prefix(input_lower, "/cmd") {
        for cmd in COMMANDS {
            result_row := Search_Result_Row{
                type = .Command,
                cmd = cmd
            }

            append(&results, result_row)
        }
    } else {
        for it in app_state.artist_list {
            it_lower := strings.to_lower(string(it), context.temp_allocator)

            if strings.contains(it_lower, input_lower) {
                result_row := Search_Result_Row{
                    type = .Artist,
                    artist_name = it
                }

                append(&results, result_row)
            }
        }

        for &it in app_state.albums {
            album_title_lower := strings.to_lower(string(it.title), context.temp_allocator)

            if strings.contains(album_title_lower, input_lower) {
                result_row := Search_Result_Row{
                    type = .Album,
                    album = &it
                }

                // @todo
                // if artist and album title match
                // key should be artist_{value}
                // key should be album_{album_title}_{artist}
                // key should be track_{track_name}_{artist}
                //app_state.search_results[it.title] = result_row
                append(&results, result_row)
            }
        }
    }

    clear(&app_state.search_results)
    append(&app_state.search_results, ..results[:])
}

handle_main_view_keyboard_events :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Main)

    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
        if app_state.ma_sound == nil {
            return
        }

        handle_play_pause(app_state)
    }

    if rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) {
        if rl.IsKeyPressed(rl.KeyboardKey.P) {
            app_state.active_viewport = .Search
        }
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
@private
build_rows :: proc(app_state: ^App_State) {
    // @todo: do not clear until new rows are built
    clear(&app_state.rows)
    app_state.rebuild_rows = false

    pos_y : i32 = ROW_HEIGHT
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

            //pos_y += ROW_HEIGHT
        }

    }

    app_state.content_max_height = pos_y

    assert(app_state.rebuild_rows == false)
}

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

@private
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
@private
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
@private
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
@private
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

// @todo: testing
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
                track_full_path, err := filepath.join({string(app_state.library_path), line}, context.allocator)
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

// @todo: testing
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

// @todo: testing
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
    // @todo: should be able to use os.exists
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

// Update layout after window has been drawn or resized
@(private = "file")
update_layout :: proc(app_state: ^App_State) {
    // -40 := 20px padding from left and right
    app_state.side_panel_rect.height = app_state.main_panel_rect.height + app_state.main_panel_rect.y // @explain
    app_state.side_panel_option_content_rect.height = app_state.side_panel_rect.height - app_state.side_panel_options_rect.height

    app_state.main_panel_rect.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel_rect.height
    app_state.main_panel_rect.width = f32(rl.GetScreenWidth()) - app_state.side_panel_rect.width - MAIN_PANEL_PADDING_RIGHT - MAIN_PANEL_PADDING_LEFT

    app_state.playback_controls_panel_rect.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel_rect.y = app_state.main_panel_rect.height
}

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

get_track_album_cover_path :: proc(app_state: ^App_State, track: ^Track) -> cstring {
    return app_state.albums[track.album_idx].cover_art_path
}

