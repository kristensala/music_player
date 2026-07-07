package main

import "core:fmt"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "core:mem"
import "core:path/filepath"

@private
init_state :: proc() -> ^App_State {
    app_state := new(App_State)
    app_state.is_library_path_set = false
    app_state.ma_sound = nil
    app_state.audio_state = .STOPPED

    load_assets(app_state)
    load_config(app_state)


    playlist_path, err := filepath.join({app_state.library_path, ".mppl"}, context.allocator)
    assert(err == nil)
    app_state.playlist_path = playlist_path

    app_state.side_panel_rect = rl.Rectangle{
        x = 0,
        y = 0,
        width = 300
    }
    app_state.side_panel_options_rect = rl.Rectangle{
        x = app_state.side_panel_rect.x,
        y = app_state.side_panel_rect.y,
        height = 100,
        width = app_state.side_panel_rect.width,
    }
    app_state.side_panel_option_content_rect = rl.Rectangle{
        x = app_state.side_panel_rect.x,
        y = app_state.side_panel_rect.y + app_state.side_panel_options_rect.height,
        width = app_state.side_panel_rect.width,
    }

    app_state.main_panel_rect = rl.Rectangle{ x = app_state.side_panel_rect.width + 20, y = 20}
    app_state.playback_controls_panel = rl.Rectangle{ x = 0, height = 170 }

    if app_state.is_library_path_set {
        append(&app_state.artist_list, "All")
        walk_music_dir(app_state, app_state.library_path)
        build_rows(app_state) // for ui
    }

    return app_state
}

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

    app_state := init_state()

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

        if app_state.is_library_path_set {
            update_main(app_state)
            update_layout(app_state)
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        if app_state.is_library_path_set {
            draw_main(app_state)
        } else {
            draw_insert_library_path_screen(app_state)
        }

        rl.EndDrawing()
    }

    // cleanup
    {
        destroy_state(app_state)
    }
}


@(private = "file")
update_main :: proc(app_state: ^App_State) {
    app_state.current_frame_rendered += 1

    invalidate_cache(app_state)
    process_album_art_queue(app_state)
    handle_keyboard_events(app_state)

    if ma.sound_at_end(app_state.ma_sound) {
        handle_next_song_pick(app_state)
    }
}

// @todo: directory picker button
@private
draw_insert_library_path_screen :: proc(app_state: ^App_State) {
    rl.DrawText("Set LIBRARY_PATH in ~/.config/music_player/config", 100, 100, FONT_30, rl.BLACK)
}

@(private = "file")
draw_main :: proc(app_state: ^App_State) {
    side_panel_draw(app_state)
    draw_main_panel_content(app_state)

    // Bottom bar
    {
        rl.DrawLineEx(
            {0, app_state.main_panel_rect.y + app_state.main_panel_rect.height}, 
            {f32(rl.GetScreenWidth()), app_state.main_panel_rect.y + app_state.main_panel_rect.height},
            1.5,
            rl.LIGHTGRAY
        )
        draw_playback_controls(app_state)

        // Display currently playing track
        {
            currently_playing_track_title : cstring = ""
            currently_playing_track_album : cstring = ""
            currently_playing_artist : cstring = ""
            if app_state.currently_playing_track != nil {
                currently_playing_track_title = app_state.currently_playing_track.title
                currently_playing_track_album = app_state.currently_playing_track.album
                currently_playing_artist = app_state.currently_playing_track.artist
            }

            rl.DrawTextEx(
                app_state.fonts[FONT_18],
                currently_playing_track_title,
                {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 70)},
                FONT_18, 0, rl.BLACK)

            rl.DrawTextEx(
                app_state.fonts[FONT_18],
                currently_playing_artist,
                {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 50)},
                FONT_18, 0, rl.PURPLE)

            rl.DrawTextEx(
                app_state.fonts[FONT_18],
                currently_playing_track_album,
                {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 30)},
                FONT_18, 0, rl.GRAY)
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
                {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - 50)},
                f32(rl.GetScreenWidth() - 100),
                10)
        }
    }
}

@(private = "file")
draw_playback_controls :: proc(app_state: ^App_State) {
    play_pause_button_bounds := rl.Rectangle{
        x = (app_state.playback_controls_panel.width / 2) - (PLAYBACK_BUTTON_SIZE / 2),
        y = f32(rl.GetScreenHeight() - 110),
        width = 50,
        height = 50
    }

    if app_state.audio_state == .PLAYING {
        rl.DrawTexture(
            app_state.pause_button_texture,
            i32(play_pause_button_bounds.x), i32(play_pause_button_bounds.y),
            rl.BLACK)
    } else if app_state.audio_state == .PAUSED || app_state.audio_state == .STOPPED {
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
            y = f32(rl.GetScreenHeight() - 110),
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
            y = f32(rl.GetScreenHeight() - 110),
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
    pos_y : f32 = app_state.side_panel_option_content_rect.y + 10
    end_y := app_state.side_panel_option_content_rect.height + app_state.side_panel_option_content_rect.y

    start := i32(app_state.side_panel_scroll_offset / SIDE_PANEL_ROW_HEIGHT)
    for artist in app_state.artist_list[start:] {
        if pos_y >= end_y {
            break
        }

        artist_txt_measurements := rl.MeasureTextEx(app_state.fonts[20], artist, FONT_20, 0)
        artist_item_bounds := rl.Rectangle{
            x = 0,
            y = pos_y,
            width = app_state.side_panel_option_content_rect.width,
            height = SIDE_PANEL_ROW_HEIGHT
        }

        if artist == app_state.current_selected_artist || (artist == "All" && app_state.current_selected_artist == nil) {
            rl.DrawRectangleRec(artist_item_bounds, rl.LIGHTGRAY)
        }

        // center text
        txt_y := ((artist_item_bounds.height - artist_txt_measurements.y) / 2) + artist_item_bounds.y

        txt_left_padding : f32 = 20
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            artist,
            {artist_item_bounds.x + txt_left_padding, txt_y},
            FONT_20, 0, rl.BLACK)

        pos_y += artist_item_bounds.height

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_option_content_rect) {
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), artist_item_bounds) {
                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    if artist == "All" {
                        app_state.current_selected_artist = nil
                    } else {
                        app_state.current_selected_artist = artist
                    }
                    app_state.main_panel_scroll_offset = 0
                    build_rows(app_state)
                }
            }
        }
    }

    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_option_content_rect) {
        if wheel < 0 { // scroll down
            app_state.side_panel_scroll_offset = app_state.side_panel_scroll_offset + (SIDE_PANEL_ROW_HEIGHT * SCROLL_INCREMENT)
            if app_state.side_panel_scroll_offset >= (f32(len(app_state.artist_list) + 1) * SIDE_PANEL_ROW_HEIGHT) - app_state.side_panel_option_content_rect.height {
                app_state.side_panel_scroll_offset = (f32(len(app_state.artist_list) + 1) * SIDE_PANEL_ROW_HEIGHT) - app_state.side_panel_option_content_rect.height
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
    //rl.DrawRectangleRec(app_state.side_panel_options_rect, rl.ORANGE)
    //rl.DrawRectangleRec(app_state.side_panel_option_content_rect, rl.GREEN)
    {
        // @todo: draw options
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Artists",
            {app_state.side_panel_rect.x + 20, app_state.side_panel_rect.y + 20},
            FONT_20,
            0,
            rl.BLACK)

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Playlists",
            {app_state.side_panel_rect.x + 20, app_state.side_panel_rect.y + 50},
            FONT_20,
            0,
            rl.BLACK)
    }

    // horizontal line
    rl.DrawLineEx(
        {0, app_state.side_panel_options_rect.y + app_state.side_panel_options_rect.height},
        {app_state.side_panel_options_rect.width, app_state.side_panel_options_rect.y + app_state.side_panel_options_rect.height},
        1.5,
        rl.LIGHTGRAY)


    rl.BeginScissorMode(
        i32(app_state.side_panel_option_content_rect.x),
        i32(app_state.side_panel_option_content_rect.y),
        i32(app_state.side_panel_option_content_rect.width),
        i32(app_state.side_panel_option_content_rect.height))

    draw_artist_list(app_state)

    rl.EndScissorMode()

    rl.DrawLineEx(
        {app_state.side_panel_rect.x + app_state.side_panel_rect.width, 0},
        {app_state.side_panel_rect.x + app_state.side_panel_rect.width, app_state.main_panel_rect.y + app_state.main_panel_rect.height},
        1.5,
        rl.LIGHTGRAY
    )
}

@(private = "file")
draw_main_panel_content :: proc(app_state: ^App_State) {
    rl.BeginScissorMode(
        i32(app_state.main_panel_rect.x),
        i32(app_state.main_panel_rect.y),
        i32(app_state.main_panel_rect.width),
        i32(app_state.main_panel_rect.height))

    pos_y := app_state.main_panel_rect.y

    start := i32(app_state.main_panel_scroll_offset / ROW_HEIGHT)
    if start > i32(len(app_state.rows) - 1) {
        start = i32(len(app_state.rows) - 1)
    }

    for row, row_idx in app_state.rows[start:] {
        // 300: pre-fetch some rows
        // then some of the covers are pre-fetched and there is no delay
        if pos_y >= app_state.main_panel_rect.height + 300 do break
        if row == nil {
            pos_y += ROW_HEIGHT
            continue
        }

        if row.is_album_row {
            pos_y += ROW_HEIGHT
            album_title_row_draw(app_state, row, &pos_y)
        } else {
            track_list_item_draw(app_state, pos_y, row)
            pos_y += ROW_HEIGHT
        }
    }

    rl.EndScissorMode()

    // Handle main panel scrolling
    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel_rect) {
        if wheel < 0 { // scroll down
            //fmt.printfln("max height: %i; offset: %i; panel height: %f", app_state.content_max_height, app_state.main_panel_scroll_offset, app_state.main_panel.height)
            if app_state.main_panel_scroll_offset + i32(app_state.main_panel_rect.height) < app_state.content_max_height + 150 { // 150 just a random buffer to fix minor calcualtion mistakes
                app_state.main_panel_scroll_offset += ROW_HEIGHT * 5
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
}

@private
handle_track_selection :: proc(app_state: ^App_State, selected_track: ^Track) {
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
            app_state.audio_state = .PLAYING
            app_state.currently_playing_track = selected_track
        }
    }
}

@private
album_title_row_draw :: proc(app_state: ^App_State, row: ^Row, pos_y: ^f32) {
    album := &app_state.albums[row.album_idx]

    list_item := rl.Rectangle{
        x = app_state.main_panel_rect.x,
        y = pos_y^,
        width = app_state.main_panel_rect.width,
        height = ROW_HEIGHT
    }
    text_measurement := rl.MeasureTextEx(app_state.fonts[FONT_30], album.title, FONT_30, 0)

    rl.DrawTextEx(
        app_state.fonts[FONT_30],
        album.title,
        { app_state.main_panel_rect.x, pos_y^},
        FONT_30,
        0,
        rl.BLACK)

    rl.DrawLine(
        i32(text_measurement.x + app_state.main_panel_rect.x + 20), 
        i32(pos_y^ + FONT_30 / 2),
        i32(app_state.main_panel_rect.width),
        i32(pos_y^ + FONT_30 / 2),
        rl.PURPLE)

    pos_y^ += ROW_HEIGHT

    if album.cover_art_cache_entry_idx >= 0 {
        cache_entry := app_state.album_art_cache.entries[album.cover_art_cache_entry_idx]
        cache_entry.frame = app_state.current_frame_rendered
        rl.DrawTexture(cache_entry.texture, i32(app_state.main_panel_rect.x), i32(pos_y^), rl.WHITE)
    } else {
        if len(album.cover_art_path) > 0 {
            fmt.println("add album to queue: ", album.title)
            request_cover_load(&app_state.album_art_load_queue, row.album_idx)
        } else { // now cover. Load default placeholder
            rl.DrawTexture(app_state.default_album_cover_texture, i32(app_state.main_panel_rect.x), i32(pos_y^), rl.WHITE)
        }
    }

}

@private
track_list_item_draw :: proc(app_state: ^App_State, pos_y: f32, row: ^Row) {
    list_item := rl.Rectangle{
        x = app_state.main_panel_rect.x + TRACK_LIST_OFFSET_X,
        y = pos_y,
        width = app_state.main_panel_rect.width,
        height = ROW_HEIGHT
    }

    // detect track clicked
    if (
        rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) &&
        rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel_rect)
    ) {
        // highlight
        rl.DrawRectangleRec(list_item, rl.ORANGE)

        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            handle_track_selection(app_state, row.track)
        }
    }

    text_measurement := rl.MeasureTextEx(app_state.fonts[FONT_20], "placeholder", FONT_20, 0)
    txt_y := ((list_item.height - text_measurement.y) / 2) + list_item.y

    txt_color := rl.BLACK
    is_playing := app_state.currently_playing_track != nil && row.track.file_path == app_state.currently_playing_track.file_path
    if is_playing {
        txt_color = rl.PURPLE
    }

    // artist - album - title
    {
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            row.track.artist,
            { list_item.x + 10, txt_y},
            f32(FONT_20),
            0,
            txt_color)

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
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
            app_state.fonts[FONT_20],
            title,
            { list_item.x + 1000, txt_y},
            f32(FONT_20),
            0,
            txt_color)
    }
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

    for entry in app_state.album_art_cache.entries {
        if entry == nil do continue
        rl.UnloadTexture(entry.texture)
    }

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


    rl.UnloadTexture(app_state.default_album_cover_texture)
    rl.UnloadTexture(app_state.play_button_texture)
    rl.UnloadTexture(app_state.pause_button_texture)
    rl.UnloadTexture(app_state.next_button_texture)
    rl.UnloadTexture(app_state.previous_button_texture)

    for key, value in app_state.fonts {
        rl.UnloadFont(value)
    }
    delete(app_state.fonts)
    delete(app_state.library_path)
    delete(app_state.playlist_path)

    free(app_state)
}

@private
load_assets :: proc(app_state: ^App_State) {
    // fonts
    {
        font_16 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_18, nil, 0)
        font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_20, nil, 0)
        font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", FONT_30, nil, 0)

        fonts := make(map[i32]rl.Font)
        fonts[FONT_18] = font_16
        fonts[FONT_20] = font_20
        fonts[FONT_30] = font_30

        app_state.fonts = fonts
    }

    // album art placeholder
    {
        album_placeholder_img := rl.LoadImage("./res/album_placeholder.png")
        rl.ImageResize(&album_placeholder_img, 200, 200)
        app_state.default_album_cover_texture = rl.LoadTextureFromImage(album_placeholder_img)
        rl.UnloadImage(album_placeholder_img)
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
}

@private
update_layout :: proc(app_state: ^App_State) {
    // -40 := 20px padding from left and right
    app_state.main_panel_rect.width = f32(rl.GetScreenWidth() - 40)
    app_state.main_panel_rect.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel.height
    app_state.side_panel_rect.height = app_state.main_panel_rect.height + app_state.main_panel_rect.y // @explain
    app_state.side_panel_option_content_rect.height = app_state.side_panel_rect.height - app_state.side_panel_options_rect.height

    app_state.playback_controls_panel.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel.y = app_state.main_panel_rect.height
}
