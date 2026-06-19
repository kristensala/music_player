package main

import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import "core:os"
import ma "vendor:miniaudio"

GUI_PADDING :: 50
SCROLL :: 200

App_State :: struct {
    font: map[i32]rl.Font,
    music_dir: string,

    tracks: [dynamic]Track,
    albums: [dynamic]Album,
    playlists: [dynamic]Playlist,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing: ^Track,

    main_panel: rl.Rectangle,
    main_panel_scroll_offset: i32,
    main_panel_content: Content,

    bottom_bar: rl.Rectangle, // track progress, playback buttons etc
    right_panel: rl.Rectangle, // if album selected, display album tracks
}

Content :: enum {
    Track_List,
    Albums,
    Playlists
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
    tracks: [dynamic]Track
}

Track :: struct {
    title: string,
    artist: string,
    album: Album,
    duration_seconds: i8,
    file_path: string,

    is_playing: bool
}

Album :: struct {
    title: string,
    artist: string,
    cover_art: string,
    tracks: [dynamic]Track,

    rect: rl.Rectangle
}

@private
dummy_data :: proc() -> ^App_State {
    app_state := new(App_State)

    album_one := Album{
        title = "Keep It Quiet",
        artist = "Greyhaven",
    }
    song_one := Track{
        title = "Burn a Miracle",
        artist = "Greyhaven",
    }
    song_two := Track{
        title = "Cemetery Sun",
        artist = "Greyhaven",
    }

    append(&album_one.tracks, song_one)
    append(&album_one.tracks, song_two)
    append(&app_state.albums, album_one)

    album_two := Album{
        title = "Keep It Quiet",
        artist = "Greyhaven",
    }
    s2 := Track{
        title = "Burn a Miracle",
        artist = "Greyhaven",
    }
    s3 := Track{
        title = "Cemetery Sun",
        artist = "Greyhaven",
    }
    append(&album_two.tracks, s2)
    append(&album_two.tracks, s3)
    append(&app_state.albums, album_two)

    for i in 0..<100 {
        t := Track{
            title = fmt.tprintf("track_%d", i),
            artist = fmt.tprintf("artist_%d", i),
        }

        append(&app_state.tracks, t)
    }

    return app_state

}

init_app :: proc() -> ^App_State {
    app_state := new(App_State)

    // walk_music_dir()
    // build tracks list and based on it albums

    return app_state
}

@private
clean_state :: proc(app_state: ^App_State) {
    delete(app_state.tracks)

    for a in app_state.albums {
        delete(a.tracks)
    }
    delete(app_state.albums)

    for p in app_state.playlists {
        delete(p.tracks)
    }
    delete(app_state.playlists)
    free(app_state)
}

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1000, 800, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", 20, nil, 0)
    defer rl.UnloadFont(font_20)

    font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", 30, nil, 0)
    defer rl.UnloadFont(font_30)

    fonts := make(map[i32]rl.Font)
    defer delete(fonts)

    fonts[20] = font_20
    fonts[30] = font_30

    app_state := dummy_data()
    app_state.font = fonts
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.main_panel = rl.Rectangle{
        x = 20,
        y = 20
    }
    app_state.main_panel_scroll_offset = 20

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

        app_state.main_panel.width = f32(rl.GetScreenWidth() - 40)
        app_state.main_panel.height = f32(rl.GetScreenHeight() - 100)

        draw(app_state)

        rl.EndDrawing()
    }

    // cleanup
    {
        ma.sound_uninit(app_state.ma_sound)
        clean_state(app_state)
    }

}


@private
draw :: proc(app_state: ^App_State) {
    button_pressed := button(app_state.font[30] ,"this is a button", {200, 200})
    if button_pressed {
        fmt.println("custom button pressed")
    }

    // Progress bar
    {
        cursor: f32 = 0
        ma.sound_get_cursor_in_seconds(app_state.ma_sound, &cursor)

        length: f32 = 1
        ma.sound_get_length_in_seconds(app_state.ma_sound, &length)

        progress_bar(
            cursor,
            length,
            {GUI_PADDING, f32(rl.GetScreenHeight() - GUI_PADDING)},
            f32(rl.GetScreenWidth() - 100),
            10)
    }

    // @todo: scroll test
    {
        rl.DrawRectangleLinesEx(app_state.main_panel, 1, rl.GREEN)
        rl.BeginScissorMode(
            i32(app_state.main_panel.x),
            i32(app_state.main_panel.y),
            i32(app_state.main_panel.width),
            i32(app_state.main_panel.height))

        pos_x := app_state.main_panel.x
        pos_y := f32(app_state.main_panel_scroll_offset)

        card_width :f32 = 200
        card_height :f32 = 250

        padding : f32 = 10

        f := app_state.main_panel.width / f32(card_width + padding)
        padding = app_state.main_panel.width / f / (f - 1)

        row_count := 0

        for t in app_state.tracks {
            rl.DrawRectangle(i32(pos_x), i32(pos_y), i32(card_width), i32(card_height), rl.RED)
            pos_x = pos_x + card_width + padding

            window_width := rl.GetScreenWidth()
            if i32(pos_x + card_width + padding) > window_width {
                pos_x = app_state.main_panel.x
                pos_y = pos_y + padding + card_height
                row_count = row_count + 1
            }
        }

        rl.EndScissorMode()

        stop_scroll_at_end := i32(f32(row_count) * (card_height + padding) - app_state.main_panel.height)

        wheel := rl.GetMouseWheelMove()
        if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel) {
            if wheel > 0 && app_state.main_panel_scroll_offset != 20 {
                app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset + 50
            } else if wheel < 0 && math.abs(app_state.main_panel_scroll_offset) <= stop_scroll_at_end {
                app_state.main_panel_scroll_offset = app_state.main_panel_scroll_offset - 50
            }
        }

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

