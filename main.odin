package main

import "core:fmt"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:mem"

main :: proc() {
    when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1800, 1250, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_20, nil, 0)
    defer rl.UnloadFont(font_20)

    font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_30, nil, 0)
    defer rl.UnloadFont(font_30)

    fonts := make(map[i32]rl.Font)
    defer delete(fonts)

    fonts[FONT_20] = font_20
    fonts[FONT_30] = font_30

    //load_config()

    app_state := new(App_State)
    app_state.music_dir = "/home/salakris/Music/"
    app_state.font = fonts
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped

    app_state.side_panel = rl.Rectangle{
        x = 0,
        y = 0,
        width = 300
    }

    app_state.main_panel = rl.Rectangle{
        x = app_state.side_panel.width + 20,
        y = 20
    }

    app_state.playback_controls_panel = rl.Rectangle{
        x = 0,
        height = 150
    }

    // Load play button image
    {
        play_btn_img := rl.LoadImage("./res/play.png")
        rl.ImageResize(&play_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.play_button_texture =  rl.LoadTextureFromImage(play_btn_img)
        rl.UnloadImage(play_btn_img)
    }

    // Load pause button image
    {
        pause_btn_img := rl.LoadImage("./res/pause.png")
        rl.ImageResize(&pause_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.pause_button_texture =  rl.LoadTextureFromImage(pause_btn_img)
        rl.UnloadImage(pause_btn_img)
    }

    // Load next button image
    {
        next_btn_img := rl.LoadImage("./res/next.png")
        rl.ImageResize(&next_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.next_button_texture =  rl.LoadTextureFromImage(next_btn_img)
        rl.UnloadImage(next_btn_img)
    }

    // Load previous button image
    {
        prev_btn_img := rl.LoadImage("./res/previous.png")
        rl.ImageResize(&prev_btn_img, PLAYBACK_BUTTON_SIZE, PLAYBACK_BUTTON_SIZE)
        app_state.previous_button_texture =  rl.LoadTextureFromImage(prev_btn_img)
        rl.UnloadImage(prev_btn_img)
    }

    append(&app_state.artist_list, "All")
    walk_music_dir(app_state, app_state.music_dir)
    build_rows(app_state) // for ui

    engine_init_result := ma.engine_init(nil, &app_state.ma_engine)
    if engine_init_result != .SUCCESS {
        fmt.println("Could not init Mini audio engine: ", engine_init_result)
        ma.engine_uninit(&app_state.ma_engine)
        return
    }
    defer ma.engine_uninit(&app_state.ma_engine)

    was_focused := true
    for !rl.WindowShouldClose() {
        // hack to lower CPU usage when window is not focused
        is_focused := rl.IsWindowFocused()
        if is_focused != was_focused {
            rl.SetTargetFPS(is_focused ? 60 : 10)
            was_focused = is_focused
        }

        update_main(app_state)
        update_layout(app_state)

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        draw_main(app_state)

        rl.EndDrawing()
    }

    // cleanup
    {
        destroy_state(app_state)
    }
}


@(private = "file")
update_main :: proc(app_state: ^App_State) {
    process_album_art_queue(app_state)
    handle_keyboard_events(app_state)

    if ma.sound_at_end(app_state.ma_sound) {
        handle_next_song_pick(app_state)
    }
}

@(private = "file")
draw_main :: proc(app_state: ^App_State) {
    side_panel_draw(app_state)
    draw_and_handle_album_list(app_state)

    // Bottom bar
    {
        rl.DrawLineEx(
            {0, app_state.main_panel.y + app_state.main_panel.height}, 
            {f32(rl.GetScreenWidth()), app_state.main_panel.y + app_state.main_panel.height},
            1.5,
            rl.LIGHTGRAY
        )
        draw_playback_controls(app_state)

        // Display currently playing track
        {
            currently_playing : cstring = ""
            if app_state.currently_playing != nil {
                currently_playing = app_state.currently_playing.file_name
            }
            rl.DrawTextEx(
                app_state.font[FONT_20],
                currently_playing,
                {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 25)},
                FONT_20, 0, rl.BLACK)
        }

        // Progress bar
        {
            cursor: f32 = 0
            ma.sound_get_cursor_in_seconds(app_state.ma_sound, &cursor)

            length: f32 = 1
            ma.sound_get_length_in_seconds(app_state.ma_sound, &length)

            progress_bar_draw(
                cursor,
                length,
                {BOTTOM_BAR_PADDING, f32(app_state.playback_controls_panel.y + 100)},
                f32(rl.GetScreenWidth() - 100),
                10)
        }
    }
}

@(private = "file")
draw_playback_controls :: proc(app_state: ^App_State) {
    play_pause_button_bounds := rl.Rectangle{
        x = (app_state.playback_controls_panel.width / 2) - (PLAYBACK_BUTTON_SIZE / 2),
        y = (app_state.playback_controls_panel.y + 50),
        width = 50,
        height = 50
    }

    if app_state.audio_state == .Playing {
        rl.DrawTexture(
            app_state.pause_button_texture,
            i32(play_pause_button_bounds.x), i32(play_pause_button_bounds.y),
            rl.BLACK)
    } else if app_state.audio_state == .Paused || app_state.audio_state == .Stopped {
        rl.DrawTexture(
            app_state.play_button_texture,
            i32(play_pause_button_bounds.x), i32(play_pause_button_bounds.y),
            rl.BLACK)
    }

    if rl.CheckCollisionPointRec(rl.GetMousePosition(), play_pause_button_bounds) {
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            handle_play_pause(app_state)
        }
    }

    // draw next song button
    {
        next_song_button_bounds := rl.Rectangle{
            x = f32(app_state.playback_controls_panel.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) + 50,
            y = f32(app_state.playback_controls_panel.y + 50),
            width = 50,
            height = 50
        }
        rl.DrawTexture(
            app_state.next_button_texture,
            i32(next_song_button_bounds.x), i32(next_song_button_bounds.y),
            rl.BLACK)

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), next_song_button_bounds) {
            if rl.IsMouseButtonPressed(.LEFT) {
                handle_next_song_pick(app_state)
            }
        }
    }

    // draw prev song button
    {
        prev_song_button_bounds := rl.Rectangle{
            x = f32(app_state.playback_controls_panel.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) - 50,
            y = f32(app_state.playback_controls_panel.y + 50),
            width = 50,
            height = 50
        }
        rl.DrawTexture(
            app_state.previous_button_texture,
            i32(prev_song_button_bounds.x), i32(prev_song_button_bounds.y),
            rl.BLACK)
    }
}

@private
draw_artist_list :: proc(app_state: ^App_State) {
    pos_y : f32 = app_state.side_panel.y + SIDE_PANEL_ROW_HEIGHT

    start := i32(app_state.side_panel_scroll_offset / SIDE_PANEL_ROW_HEIGHT)
    for artist in app_state.artist_list[start:] {
        if pos_y >= app_state.side_panel.height {
            break
        }

        artist_txt_measurements := rl.MeasureTextEx(app_state.font[20], artist, FONT_20, 0)

        artist_item_bounds := rl.Rectangle{
            x = 0,
            y = pos_y,
            width = app_state.side_panel.width,
            height = SIDE_PANEL_ROW_HEIGHT
        }

        if artist == app_state.selected_artist || (artist == "All" && app_state.selected_artist == nil) {
            rl.DrawRectangleRec(artist_item_bounds, rl.LIGHTGRAY)
        }

        // center text
        txt_y := ((artist_item_bounds.height - artist_txt_measurements.y) / 2) + artist_item_bounds.y

        rl.DrawTextEx(
            app_state.font[FONT_20],
            artist,
            {artist_item_bounds.x + 20, txt_y},
            FONT_20, 0, rl.BLACK)

        pos_y = pos_y + artist_item_bounds.height

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel) {
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), artist_item_bounds) {
                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    if artist == "All" {
                        app_state.selected_artist = nil
                    } else {
                        app_state.selected_artist = artist
                    }
                    app_state.main_panel_scroll_offset = 0
                    build_rows(app_state)
                }
            }
        }

    }

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel) {
        if wheel < 0 { // scroll down
            app_state.side_panel_scroll_offset = app_state.side_panel_scroll_offset + (SIDE_PANEL_ROW_HEIGHT * SCROLL_INCREMENT)
            if app_state.side_panel_scroll_offset >= (f32(len(app_state.artist_list) + 2) * SIDE_PANEL_ROW_HEIGHT) - app_state.side_panel.height {
                app_state.side_panel_scroll_offset = (f32(len(app_state.artist_list) + 2) * SIDE_PANEL_ROW_HEIGHT) - app_state.side_panel.height
            }

        } else if wheel > 0 {
            app_state.side_panel_scroll_offset = app_state.side_panel_scroll_offset - (SIDE_PANEL_ROW_HEIGHT * SCROLL_INCREMENT) // five rows
            if app_state.side_panel_scroll_offset < 0 {
                app_state.side_panel_scroll_offset = 0
            }
        }
    }
}

@private
side_panel_draw :: proc(app_state: ^App_State) {
    rl.DrawLineEx(
        {app_state.side_panel.x + app_state.side_panel.width, 0},
        {app_state.side_panel.x + app_state.side_panel.width, app_state.main_panel.y + app_state.main_panel.height},
        1.5,
        rl.LIGHTGRAY
    )

    rl.BeginScissorMode(
        i32(app_state.side_panel.x),
        i32(app_state.side_panel.y),
        i32(app_state.side_panel.width),
        i32(app_state.main_panel.height))

    draw_artist_list(app_state)

    rl.EndScissorMode()
}

@(private = "file")
draw_and_handle_album_list :: proc(app_state: ^App_State) {
    selected_track, pressed := draw_main_panel_content(app_state)
    if pressed {
        if app_state.ma_sound != nil {
            ma.sound_uninit(app_state.ma_sound)
            app_state.ma_sound = nil
        }

        app_state.ma_sound = new(ma.sound)
        res := ma.sound_init_from_file(&app_state.ma_engine, selected_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
        if res != .SUCCESS {
            app_state.ma_sound = nil
            fmt.println("Could not init sound: ", res)
        } else {
            sound_start_result := ma.sound_start(app_state.ma_sound)
            if sound_start_result == .SUCCESS {
                app_state.audio_state = .Playing
                app_state.currently_playing = selected_track
            }
        }
    }
}

@(private = "file")
draw_main_panel_content :: proc(app_state: ^App_State) -> (t: ^Track, pressed: bool) {
    track_pressed := false
    pressed_track : ^Track = nil

    rl.BeginScissorMode(
        i32(app_state.main_panel.x),
        i32(app_state.main_panel.y),
        i32(app_state.main_panel.width),
        i32(app_state.main_panel.height))

    pos_y := app_state.main_panel.y

    start := i32(app_state.main_panel_scroll_offset / ROW_HEIGHT)
    if start > i32(len(app_state.rows) - 1) {
        start = i32(len(app_state.rows) - 1)
    }

    album_start_y : f32
    for row, row_idx in app_state.rows[start:] {
        if pos_y >= app_state.main_panel.height {
            break
        }

        if row.is_album_row {
            album := &app_state.albums[row.album_idx]

            pos_y += ROW_HEIGHT
            //@note: album min height should be 200px because the album art is 200x200
            if row_idx > 0 && pos_y - album_start_y < COVER_SIZE {
                pos_y = pos_y + (pos_y - album_start_y)
            }
            album_start_y = pos_y

            list_item := rl.Rectangle{
                x = app_state.main_panel.x,
                y = pos_y,
                width = app_state.main_panel.width,
                height = ROW_HEIGHT
            }
            text_measurement := rl.MeasureTextEx(app_state.font[FONT_30], album.title, FONT_30, 0)

            rl.DrawTextEx(
                app_state.font[FONT_30],
                album.title,
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

            if album.cover_art_cache_entry_idx >= 0 {
                app_state.album_art_cache.current_frame += 1
                cache_entry := &app_state.album_art_cache.entries[album.cover_art_cache_entry_idx]
                cache_entry.frame = app_state.album_art_cache.current_frame
                rl.DrawTexture(cache_entry.texture, i32(app_state.main_panel.x), i32(pos_y), rl.WHITE)
            } else {
                request_cover_load(&app_state.album_art_load_queue, row.album_idx)
            }

        } else {
            list_item := rl.Rectangle{
                x = app_state.main_panel.x + 250, // @todo
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
                    row.track.artist,
                    { list_item.x + 10, txt_y},
                    f32(FONT_20),
                    0,
                    txt_color)

                rl.DrawTextEx(
                    app_state.font[FONT_20],
                    row.track.album,
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
        if wheel < 0 { // scroll down
            offset := app_state.main_panel_scroll_offset + (ROW_HEIGHT * 5)
            if f32(offset) + app_state.main_panel.height < f32(app_state.content_max_height + 50) {
                app_state.main_panel_scroll_offset += (ROW_HEIGHT * 5)
            }
        } else if wheel > 0 { // scroll up
            offset := app_state.main_panel_scroll_offset - (ROW_HEIGHT * 5)
            if offset <= 0 {
                app_state.main_panel_scroll_offset = 0
            } else {
                app_state.main_panel_scroll_offset -= (ROW_HEIGHT * 5)
            }
        }
    }

    return pressed_track, track_pressed
}

@(private = "file")
progress_bar_draw :: proc(value: f32, max_value: f32, pos: [2]f32, w, h: f32) {
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

@private
destroy_state :: proc(app_state: ^App_State) {
    ma.sound_uninit(app_state.ma_sound)

    delete(app_state.rows)
    delete(app_state.artist_list)

    for a in app_state.albums {
        delete(a.track_indices)
        delete(a.cover_art_path)
    }
    delete(app_state.albums)

    for t in app_state.tracks {
        delete(t.file_name)
        delete(t.file_path)
        delete(t.title)
        delete(t.artist)
        delete(t.album)
    }
    delete(app_state.tracks)


    for p in app_state.playlists {
        delete(p.tracks)
    }
    delete(app_state.playlists)

    for entry in app_state.album_art_cache.entries {
        rl.UnloadTexture(entry.texture)
    }

    rl.UnloadTexture(app_state.default_album_cover_texture)
    rl.UnloadTexture(app_state.play_button_texture)
    rl.UnloadTexture(app_state.pause_button_texture)
    rl.UnloadTexture(app_state.next_button_texture)
    rl.UnloadTexture(app_state.previous_button_texture)

    free(app_state)
}

update_layout :: proc(app_state: ^App_State) {
    app_state.main_panel.width = f32(rl.GetScreenWidth() - 40)
    app_state.main_panel.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel.height
    app_state.side_panel.height = app_state.main_panel.height

    app_state.playback_controls_panel.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel.y = app_state.main_panel.height
}
