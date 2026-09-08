package main

import rl "vendor:raylib"

center_text_y :: proc(font: rl.Font, bounds: rl.Rectangle) -> f32 {
    text_measurement := rl.MeasureTextEx(font, "test", f32(font.baseSize), 0)
    txt_y := ((bounds.height - text_measurement.y) / 2) + bounds.y
    return txt_y
}

get_track_album_cover_path :: proc(app_state: ^App_State, track: ^Track) -> cstring {
    return app_state.albums[track.album_idx].cover_art_path
}
