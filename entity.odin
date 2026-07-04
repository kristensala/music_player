package main

import rl "vendor:raylib"
import ma "vendor:miniaudio"

SCROLL_INCREMENT      :: 5 // five rows
BOTTOM_BAR_PADDING    :: 50
FONT_16               :: 18
FONT_20               :: 20
FONT_30               :: 30
PLAYBACK_BUTTON_SIZE  :: 30
SIDE_PANEL_ROW_HEIGHT :: 35
ROW_HEIGHT :: 40

Row :: struct {
    is_album_row : bool, // if true then track is nil
    album_idx: i32,
    track: ^Track,
}

App_State :: struct {
    font: map[i32]rl.Font,
    music_dir: string,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,
    playlists: [dynamic]Playlist,

    // @todo: playback_queue
    //queue: [dynamic]i32, //track indices

    rows: [dynamic]^Row,
    content_max_height: i32, // in pixels

    default_album_cover_texture: rl.Texture2D,

    play_button_texture: rl.Texture2D,
    pause_button_texture: rl.Texture2D,
    next_button_texture: rl.Texture2D,
    previous_button_texture: rl.Texture2D,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing: ^Track,

    main_panel: rl.Rectangle,

    playback_controls_panel: rl.Rectangle,
    side_panel: rl.Rectangle,

    main_panel_scroll_offset: i32,
    side_panel_scroll_offset: f32,

    // filtering
    artist_list: [dynamic]cstring,
    selected_artist: cstring, // nil means show all the tracks

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

AudioState :: enum {
    Stopped,
    Playing,
    Paused
}

// @todo
// custom files
// Use DeaDBeef as an example
Playlist :: struct {
    title: string,
    tracks: [dynamic]Track
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
