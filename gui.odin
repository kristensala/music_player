package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

SCROLL_VALUE :: 100

albums_grid :: proc() -> (pressed: bool, album: ^Album) {
    return false, nil
}

tracks_list :: proc(app_state: ^App_State) -> (pressed: bool, _track: ^Track) {
    rl.BeginScissorMode(
        i32(app_state.main_panel.x),
        i32(app_state.main_panel.y),
        i32(app_state.main_panel.width),
        i32(app_state.main_panel.height))

    pos_y : f32 = f32(app_state.main_panel_scroll_offset)
    track_pressed := false
    pressed_track : ^Track = nil

    list_item_height : f32 = 40
    for album in app_state.albums {
        pos_y = pos_y + 20 // add a small margin before each album

        // Only draw what is visible to the user
        if pos_y >= app_state.main_panel.y && pos_y <= app_state.main_panel.height {
            text_measurement := rl.MeasureTextEx(app_state.font[30], album.title, 30, 0)
            rl.DrawTextEx(
                app_state.font[30],
                album.title,
                { app_state.main_panel.x, pos_y},
                30,
                0,
                rl.BLACK)
        }

        pos_y = pos_y + list_item_height

        // @todo: filter tracks and loop over the ones which are visible,
        // not all of them
        for track_idx in album.track_indices {
            list_item := rl.Rectangle{
                x = app_state.main_panel.x,
                y = pos_y,
                width = app_state.main_panel.width,
                height = list_item_height
            }

            // Only draw tracks which are visible to the user
            if pos_y >= app_state.main_panel.y && pos_y <= app_state.main_panel.height {
                track := &app_state.tracks[track_idx]

                formated_str := fmt.caprintf("%s - %s - %s", track.album, track.artist, track.title)
                defer delete(formated_str)

                text_measurement := rl.MeasureTextEx(app_state.font[20], formated_str, 20, 0)
                txt_y := ((list_item.height - text_measurement.y) / 2) + list_item.y

                rl.DrawTextEx(
                    app_state.font[20],
                    formated_str,
                    { list_item.x, txt_y},
                    20,
                    0,
                    rl.BLACK)

                rl.DrawLine(
                    0, 
                    i32(list_item.y + list_item.height + 1),
                    i32(app_state.main_panel.width),
                    i32(list_item.y + list_item.height + 1),
                    rl.LIGHTGRAY)

                if rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) &&
                    rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel)
                    {
                        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                            track_pressed = true
                            pressed_track = track
                        }
                    }
            }

            pos_y = pos_y + list_item.height
        }
    }

    rl.EndScissorMode()

    row_count := len(app_state.tracks)
    albums_count := len(app_state.albums)
    max_offset := (f32(row_count) * list_item_height) + (f32(albums_count) * (list_item_height + 20)) - app_state.main_panel.height

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel) {
        if wheel > 0 && f32(app_state.main_panel_scroll_offset) < app_state.main_panel.y {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset + SCROLL_VALUE

            if f32(app_state.main_panel_scroll_offset) > app_state.main_panel.y {
                app_state.main_panel_scroll_offset = i32(app_state.main_panel.y)
            }
        } else if wheel < 0 && math.abs(app_state.main_panel_scroll_offset) < i32(max_offset) {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset - SCROLL_VALUE

            if math.abs(app_state.main_panel_scroll_offset) > i32(max_offset) {
                app_state.main_panel_scroll_offset = i32(-max_offset)
            }
        }
    }

    return track_pressed, pressed_track
}

progress_bar :: proc(value: f32, max_value: f32, pos: [2]f32, w, h: f32) {
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
        return mouse_pos.x >= pos.x && mouse_pos.x <= pos.x + bounds.width &&
            mouse_pos.y >= pos.y && mouse_pos.y <= pos.y + bounds.height
    }

    return false
}
