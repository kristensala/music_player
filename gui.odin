package main

import "core:strings"
import "core:fmt"
import rl "vendor:raylib"

albums_grid :: proc() -> (pressed: bool, album: ^Album) {
    return false, nil
}

tracks_list :: proc(app_state: ^App_State) -> (pressed: bool, track: ^Track) {
    rl.BeginScissorMode(
        i32(app_state.main_panel.x),
        i32(app_state.main_panel.y),
        i32(app_state.main_panel.width),
        i32(app_state.main_panel.height))

    pos_y : f32 = f32(app_state.main_panel_scroll_offset)
    foo := false
    pressed_track : ^Track = nil

    for &track in app_state.tracks {
        list_item := rl.Rectangle{
            x = app_state.main_panel.x,
            y = pos_y,
            width = app_state.main_panel.width,
            height = 50
        }

        txt := strings.clone_to_cstring(fmt.tprintf("%s / (%s)", track.file_name, track.file_path))
        defer delete(txt)

        text_measurement := rl.MeasureTextEx(app_state.font[30], txt, 30, 0)
        txt_y := ((list_item.height - text_measurement.y) / 2) + list_item.y

        rl.DrawTextEx(
            app_state.font[30],
            txt,
            { list_item.x, txt_y},
            30,
            0,
            rl.BLACK)

        rl.DrawLine(
            0, 
            i32(list_item.y + list_item.height + 1),
            i32(app_state.main_panel.width),
            i32(list_item.y + list_item.height + 1),
            rl.BLACK)

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                foo = true
                pressed_track = &track
            }
        }

        pos_y = pos_y + list_item.height
    }


    rl.EndScissorMode()


    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel) {
        if wheel > 0 {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset + 100
        } else if wheel < 0 {
            app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset - 100
        }
    }

    return foo, pressed_track
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
