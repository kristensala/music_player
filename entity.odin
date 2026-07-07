package main

import rl "vendor:raylib"
import ma "vendor:miniaudio"

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

    track_indices: [dynamic]i32 // reference to the app_state.tracks @todo: should use [dynamic]^Track then I can sort the list of tracks
}

Side_Panel_Option :: enum i32 {
    Artist_List = 0,
    Playlists = 1,
    All_Music = 2 // @todo: remove all artists option from artist list and add it to the side_panel options instead. As "All Music"
}
