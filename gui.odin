package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

SCROLL_VALUE :: 100
ALBUM_COVER_SCALE :: 0.75

albums_grid :: proc() -> (pressed: bool, album: ^Album) {
    return false, nil
}

draw_tracks_list :: proc(app_state: ^App_State) -> (pressed: bool, _track: ^Track) {
    track_pressed := false
    pressed_track : ^Track = nil

    pos_y : f32 = f32(app_state.main_panel_scroll_offset)
    list_item_height : f32 = 40
    album_padding_bottom : f32 = 40
    album_content_start : f32 = 40
    album_height : f32 = 0
    album_title_font_size : i32 = 30
    max_content_height : f32 = 0
    tracks_start_pos_x : f32 = 250

    rl.BeginScissorMode(
        i32(app_state.main_panel.x),
        i32(app_state.main_panel.y),
        i32(app_state.main_panel.width),
        i32(app_state.main_panel.height))

    for album, album_idx in app_state.albums {
        // Only draw what is visible to the user
        if is_in_view(pos_y, app_state.main_panel) {
            text_measurement := rl.MeasureTextEx(app_state.font[album_title_font_size], album.title, f32(album_title_font_size), 0)

            rl.DrawTextEx(
                app_state.font[album_title_font_size],
                album.title,
                { app_state.main_panel.x, pos_y},
                f32(album_title_font_size),
                0,
                rl.BLACK)

            rl.DrawLine(
                i32(text_measurement.x + app_state.main_panel.x + 20), 
                i32(pos_y + f32(album_title_font_size / 2)),
                i32(app_state.main_panel.width),
                i32(pos_y + f32(album_title_font_size / 2)),
                rl.PURPLE)
        }

        // Draw album cover
        {
            // Draw texture even if it is showing on screen half way
            texture_height := f32(app_state.default_album_cover_texture.height)
            if pos_y + texture_height >= app_state.main_panel.y && pos_y <= app_state.main_panel.height {
                rl.DrawTextureEx(app_state.default_album_cover_texture, {0, pos_y + list_item_height}, 0, ALBUM_COVER_SCALE, rl.WHITE)
            }
        }

        pos_y = pos_y + album_content_start
        album_height := album_content_start

        // @todo: filter tracks and loop over the ones which are visible,
        // not all of them
        for track_idx, idx in album.track_indices {
            list_item := rl.Rectangle{
                x = tracks_start_pos_x,
                y = pos_y,
                width = app_state.main_panel.width,
                height = list_item_height
            }

            // Only draw tracks which are visible to the user
            if is_in_view(pos_y, app_state.main_panel) {
                track := app_state.tracks[track_idx]

                if (
                    rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) &&
                    rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel)
                ) {
                    rl.DrawRectangleRec(list_item, rl.ORANGE)

                    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                        track_pressed = true
                        pressed_track = track
                    }
                }

                text_measurement := rl.MeasureTextEx(app_state.font[20], "placeholder", 20, 0)
                txt_y := ((list_item.height - text_measurement.y) / 2) + list_item.y

                txt_color := rl.BLACK
                is_playing := app_state.currently_playing != nil && track.file_path == app_state.currently_playing.file_path
                if is_playing {
                    txt_color = rl.PURPLE
                }

                // display track text
                {
                    rl.DrawTextEx(
                        app_state.font[20],
                        track.album,
                        { list_item.x + 10, txt_y},
                        20,
                        0,
                        txt_color)

                    rl.DrawTextEx(
                        app_state.font[20],
                        track.artist,
                        { list_item.x + 500, txt_y},
                        20,
                        0,
                        txt_color)

                    title := track.title
                    if len(title) == 0 {
                        title = track.file_name
                    }
                    rl.DrawTextEx(
                        app_state.font[20],
                        title,
                        { list_item.x + 1000, txt_y},
                        20,
                        0,
                        txt_color)
                }

                rl.DrawLine(
                    i32(tracks_start_pos_x), 
                    i32(list_item.y + list_item.height),
                    i32(app_state.main_panel.width + 20),
                    i32(list_item.y + list_item.height),
                    rl.LIGHTGRAY)
            }

            pos_y = pos_y + list_item.height
            album_height = album_height + list_item_height
        }

        if album_height < f32(album.cover_img_texture.height) {
            album_height = f32(album.cover_img_texture.height) * ALBUM_COVER_SCALE
            // split the difference between cover art height and track list height
            pos_y = pos_y + (album_height - (f32(len(album.track_indices)) * list_item_height))
        }

        pos_y = pos_y + album_padding_bottom

        max_content_height = max_content_height + album_height + album_padding_bottom
    }

    rl.EndScissorMode()

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel) {
        if wheel > 0 && f32(app_state.main_panel_scroll_offset) < app_state.main_panel.y {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset + SCROLL_VALUE

            if f32(app_state.main_panel_scroll_offset) > app_state.main_panel.y {
                app_state.main_panel_scroll_offset = i32(app_state.main_panel.y)
            }
        } else if wheel < 0 && max_content_height > app_state.main_panel.height && f32(math.abs(app_state.main_panel_scroll_offset)) < max_content_height {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset - SCROLL_VALUE

            if f32(math.abs(app_state.main_panel_scroll_offset)) > max_content_height {
                app_state.main_panel_scroll_offset = i32(-max_content_height)
            }
        }
    }

    return track_pressed, pressed_track
}

draw_progress_bar :: proc(value: f32, max_value: f32, pos: [2]f32, w, h: f32) {
    bounds := rl.Rectangle{
        x = pos.x,
        y = pos.y,
        width = w,
        height = h
    }

    roundness: f32 = 0.2
    {
        progress := value * bounds.width / max_value
        progress_rect := rl.Rectangle{
            x = pos.x,
            y = pos.y + 0.4,
            width = progress,
            height = h
        }
        rl.DrawRectangleRec(progress_rect, rl.PURPLE)
    }

    rl.DrawRectangleRoundedLinesEx(
        bounds,
        0.1,
        0, 2, rl.BLACK)
}

button :: proc(font: rl.Font, text: cstring, pos: [2]f32) -> bool {
    padding_horizontal: f32 = 20
    padding_vertical: f32 = 10
    text_measurement := rl.MeasureTextEx(font, text, f32(font.baseSize), 0)

    bounds := rl.Rectangle{
        x = pos.x,
        y = pos.y,
        width = text_measurement.x + padding_horizontal,
        height = text_measurement.y + padding_vertical
    }

    roundness: f32 = 0.2
    rl.DrawRectangleRounded(bounds, roundness, 0, rl.LIGHTGRAY)
    rl.DrawTextEx(
        font,
        text,
        {pos.x + (padding_horizontal / 2), pos.y + (padding_vertical / 2)},
        f32(font.baseSize), 0, rl.BLACK)

    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
        mouse_pos := rl.GetMousePosition()
        return rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    }

    return false
}

@private
is_in_view :: proc(point: f32, panel: rl.Rectangle) -> bool {
    return point >= panel.y && point <= panel.height 
}
