package main

import rl "vendor:raylib"

main :: proc() {
    rl.InitWindow(1000, 800, "music_player")
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)
        rl.EndDrawing()
    }

    rl.CloseWindow()
}
