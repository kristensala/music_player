package main

import "core:fmt"
import rl "vendor:raylib"
import "core:os"
import ma "vendor:miniaudio"

App_State :: struct {
    font: rl.Font,
    music_dir: string,
    albums: [dynamic]Album,
    playlists: [dynamic]Playlist,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState
}

AudioState :: enum {
    Stopped,
    Playing,
    Paused
}

// custom files
// Use DeaDBeef as an example
Playlist :: struct {
    title: string,
    songs: [dynamic]Song
}

Song :: struct {
    title: string,
    artist: string,
    duration_seconds: i8,
    file_path: string,

    is_playing: bool
}

Album :: struct {
    title: string,
    artist: string,
    cover_art: string,
    songs: [dynamic]Song,

    rect: rl.Rectangle
}

@private
dummy_data :: proc() -> ^App_State {
    app_state := new(App_State)

    album_one := Album{
        title = "Keep It Quiet",
        artist = "Greyhaven",
    }
    song_one := Song{
        title = "Burn a Miracle",
        artist = "Greyhaven",
    }
    song_two := Song{
        title = "Cemetery Sun",
        artist = "Greyhaven",
    }

    append(&album_one.songs, song_one)
    append(&album_one.songs, song_two)
    append(&app_state.albums, album_one)

    album_two := Album{
        title = "Keep It Quiet",
        artist = "Greyhaven",
    }
    s2 := Song{
        title = "Burn a Miracle",
        artist = "Greyhaven",
    }
    s3 := Song{
        title = "Cemetery Sun",
        artist = "Greyhaven",
    }
    append(&album_two.songs, s2)
    append(&album_two.songs, s3)
    append(&app_state.albums, album_two)

    return app_state

}

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1000, 800, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    font := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", 30, nil, 250)
    defer rl.UnloadFont(font)

    app_state := dummy_data()
    app_state.font = font
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped

    engine_init_result := ma.engine_init(nil, &app_state.ma_engine)
    if engine_init_result != .SUCCESS {
        fmt.println("Could not init Mini audio engine: ", engine_init_result)
        ma.engine_uninit(&app_state.ma_engine)
        return
    }
    defer ma.engine_uninit(&app_state.ma_engine)


    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        draw(app_state)

        rl.EndDrawing()
    }

    // cleanup
    {
        ma.sound_uninit(app_state.ma_sound)

        free(app_state)
    }

}

@private
draw :: proc(app_state: ^App_State) {
    rl.DrawTextEx(app_state.font, "test", {10, 10}, f32(app_state.font.baseSize), 1, rl.BLACK)

    foo := button(app_state.font ,"this is a button", {200, 200})
    if foo {
        fmt.println("custom button pressed: ", foo)
    }

    // Progress bar
    {
        cursor: f32 = 0
        ma.sound_get_cursor_in_seconds(app_state.ma_sound, &cursor)

        length: f32 = 1
        ma.sound_get_length_in_seconds(app_state.ma_sound, &length)

        progress_bar_rect := rl.Rectangle{
            x = 50,
            y = f32(rl.GetScreenHeight() - 50),
            width = f32(rl.GetScreenWidth() - 100),
            height = 10
        }
        rl.GuiProgressBar(progress_bar_rect, "cursor", "length", &cursor, 0, length)
    }

    // play/pause button
    {
        play_btn := rl.Rectangle{
            x = 50,
            y = 50,
            width = 50,
            height = 50
        }
        pressed := rl.GuiButton(play_btn, "Play")
        if pressed {
            if app_state.audio_state == .Playing {
                stop_res := ma.sound_stop(app_state.ma_sound)
                if stop_res == .SUCCESS {
                    app_state.audio_state = .Paused
                }
            } else {
                if app_state.ma_sound != nil {
                    sound_start_result := ma.sound_start(app_state.ma_sound)
                    if sound_start_result == .SUCCESS {
                        app_state.audio_state = .Playing
                    }
                } else {
                    app_state.ma_sound = new(ma.sound)

                    res := ma.sound_init_from_file(&app_state.ma_engine, "/home/salakris/Music/3_Doors_Down/Away_From_The_Sun/01-3 Doors Down - When I'm Gone.mp3", {.STREAM}, nil, nil, app_state.ma_sound)
                    if res != .SUCCESS {
                        fmt.println("Could not init sound: ", res)
                    } else {
                        sound_start_result := ma.sound_start(app_state.ma_sound)
                        if sound_start_result == .SUCCESS {
                            app_state.audio_state = .Playing
                        }
                    }
                }
            }
        }
    }

    pos_x := 10
    pos_y := 10

    card_width := 200
    card_height := 250

    padding := 10

    /*for i in 0..<100 {
        rl.DrawRectangle(i32(pos_x), i32(pos_y), i32(card_width), i32(card_height), rl.RED)
        pos_x = pos_x + card_width + padding

        window_width := rl.GetScreenWidth()
        if i32(pos_x + card_width + padding) > window_width {
            pos_x = 10
            pos_y = pos_y + padding + card_height
        }
    }*/
}

@private
progress_bar_draw :: proc() {
}

@private
walk_music_dir :: proc(path: string) {
    data, err := os.read_directory_by_path(path, 0, context.allocator)
    if err != nil {
        fmt.printf("Could not read the dir", err)
        return
    }
    defer delete(data)

    for d in data {
        if d.type == .Directory {
            walk_music_dir(d.fullpath)
        } else {
            fmt.println(d.name)
        }
    }

}

