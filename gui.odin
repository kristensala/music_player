package main

import rl "vendor:raylib"

SCROLL_INCREMENT :: 5 // five rows
ALBUM_COVER_SCALE :: 2

ROW_HEIGHT :: 40

Row :: struct {
    is_album_title_row : bool,
    album_title        : ^cstring,
    track              : ^Track,
}

draw_content :: proc(app_state: ^App_State) -> (t: ^Track, pressed: bool) {
    track_pressed         := false
    pressed_track         : ^Track = nil

    rl.BeginScissorMode(
        i32(app_state.main_panel.x),
        i32(app_state.main_panel.y),
        i32(app_state.main_panel.width),
        i32(app_state.main_panel.height))

    start := app_state.current_scroll_idx
    end := app_state.current_scroll_idx + app_state.max_rows_count_to_render
    pos_y := app_state.main_panel.x

    for row in app_state.rows[start:end] {
        if row.is_album_title_row {
            pos_y = pos_y + ROW_HEIGHT
            list_item := rl.Rectangle{
                x = app_state.main_panel.x,
                y = pos_y,
                width = app_state.main_panel.width,
                height = ROW_HEIGHT
            }
            text_measurement := rl.MeasureTextEx(app_state.font[FONT_30], row.album_title^, FONT_30, 0)

            rl.DrawTextEx(
                app_state.font[FONT_30],
                row.album_title^,
                { app_state.main_panel.x, pos_y},
                FONT_30,
                0,
                rl.BLACK)

            rl.DrawLine(
                i32(text_measurement.x + app_state.main_panel.x + 20), 
                i32(pos_y + FONT_30 / 2),
                i32(app_state.main_panel.width),
                i32(pos_y + FONT_30 / 2),
                rl.PURPLE)

            pos_y = pos_y + ROW_HEIGHT

        } else {
            list_item := rl.Rectangle{
                x = 250,
                y = pos_y,
                width = app_state.main_panel.width,
                height = ROW_HEIGHT
            }

            // handle row clicked
            {
                if (
                    rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) &&
                    rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel)
                ) {
                    rl.DrawRectangleRec(list_item, rl.ORANGE)

                    if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                        track_pressed = true
                        pressed_track = row.track
                    }
                }
            }

            text_measurement := rl.MeasureTextEx(app_state.font[FONT_20], "placeholder", FONT_20, 0)
            txt_y := ((list_item.height - text_measurement.y) / 2) + list_item.y

            txt_color := rl.BLACK
            is_playing := app_state.currently_playing != nil && row.track.file_path == app_state.currently_playing.file_path
            if is_playing {
                txt_color = rl.PURPLE
            }

            // display track text
            {
                rl.DrawTextEx(
                    app_state.font[FONT_20],
                    row.track.album,
                    { list_item.x + 10, txt_y},
                    f32(FONT_20),
                    0,
                    txt_color)

                rl.DrawTextEx(
                    app_state.font[FONT_20],
                    row.track.artist,
                    { list_item.x + 500, txt_y},
                    f32(FONT_20),
                    0,
                    txt_color)

                title := row.track.title
                if len(title) == 0 {
                    title = row.track.file_name
                }
                rl.DrawTextEx(
                    app_state.font[FONT_20],
                    title,
                    { list_item.x + 1000, txt_y},
                    f32(FONT_20),
                    0,
                    txt_color)
            }
            pos_y = pos_y + ROW_HEIGHT
        }

    }

    rl.EndScissorMode()

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel) {
        // scroll down
        if wheel < 0 {
            value := app_state.current_scroll_idx + SCROLL_INCREMENT
            max_allowed_value := i32(len(app_state.rows)) - 1 - app_state.max_rows_count_to_render - 1
            if value >= max_allowed_value {
                app_state.current_scroll_idx = max_allowed_value
            } else {
                app_state.current_scroll_idx = value
            }

        } else if wheel > 0 { // scroll up
            value := app_state.current_scroll_idx - SCROLL_INCREMENT
            if value <= 0 {
                app_state.current_scroll_idx = 0
            } else {
                app_state.current_scroll_idx = value
            }
        }
    }

    return pressed_track, track_pressed
}

build_rows :: proc(app_state: ^App_State) {
    rows : [dynamic]^Row

    pos_y : i32 = i32(app_state.main_panel.y)
    for album in app_state.albums {
        album_title_row := new(Row)
        album_title_row.is_album_title_row = true
        album_title_row.album_title = &album.title

        pos_y = pos_y + ROW_HEIGHT

        append(&rows, album_title_row)

        // @todo: next should be cover art row

        for track_idx in album.track_indices {
            track := app_state.tracks[track_idx]
            assert(track != nil)

            track_row := new(Row)
            track_row.track = track

            pos_y = pos_y + ROW_HEIGHT

            append(&rows, track_row)
        }

        pos_y = pos_y + 40 // padding after the album
    }

    app_state.rows = rows
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
