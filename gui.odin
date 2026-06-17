package main

import rl "vendor:raylib"

albums_grid :: proc() {
}

tracks_list :: proc() {
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
