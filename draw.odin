package main

import "core:fmt"
import rl "vendor:raylib"
import ma "vendor:miniaudio"

@(private)
draw_main :: proc(app_state: ^App_State) {
    draw_side_panel(app_state)
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
                currently_playing_track_album = app_state.currently_playing_track.album_title
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

            draw_progress_bar(
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
        x = (app_state.playback_controls_panel_rect.width / 2) - (PLAYBACK_BUTTON_SIZE / 2),
        y = f32(rl.GetScreenHeight() - 110),
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
            x = f32(app_state.playback_controls_panel_rect.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) + 50,
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
                handle_next_song_pick_v2(app_state)
            }
        }
    }

    // draw prev song button
    {
        prev_song_button_bounds := rl.Rectangle{
            x = f32(app_state.playback_controls_panel_rect.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) - 50,
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
handle_play_pause :: proc(app_state: ^App_State) {
    if app_state.audio_state == .Playing {
        stop_response := ma.sound_stop(app_state.ma_sound)
        if stop_response == .SUCCESS {
            app_state.audio_state = .Paused
        } else {
            fmt.eprintln("Could not stop the sound: ", stop_response)
        }
    } else if app_state.audio_state == .Paused && app_state.ma_sound != nil {
        start_response := ma.sound_start(app_state.ma_sound)
        if start_response == .SUCCESS {
            app_state.audio_state = .Playing
        } else {
            fmt.eprintln("Could not start the sound: ", start_response)
        }
    }
}

handle_next_song_pick_v2 :: proc(app_state: ^App_State) {
    assert(app_state.currently_playing_track != nil)

    queue_len := i32(len(app_state.queue))
    if queue_len == 0 {
        fmt.println("Nothing in queue")
        return
    }

    if app_state.current_position_in_queue == queue_len - 1 {
        fmt.println("End of queue")
        return
    }

    app_state.current_position_in_queue += 1
    fmt.println("queue pos: ", app_state.current_position_in_queue)
    next_track_idx := app_state.queue[app_state.current_position_in_queue]
    next_track := &app_state.tracks[next_track_idx]

    ma.sound_uninit(app_state.ma_sound)
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.currently_playing_track = nil
    app_state.currently_playing_track_idx = -1

    app_state.ma_sound = new(ma.sound)
    res := ma.sound_init_from_file(&app_state.ma_engine, next_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
    if res != .SUCCESS {
        app_state.ma_sound = nil
        fmt.println("Could not start the next track")
    } else {
        sound_start_result := ma.sound_start(app_state.ma_sound)
        if sound_start_result == .SUCCESS {
            app_state.audio_state = .Playing
            app_state.currently_playing_track = next_track
            app_state.currently_playing_track_idx = next_track_idx
        }
    }
}

@private
handle_next_song_pick :: proc(app_state: ^App_State) {
    current_album := app_state.albums[app_state.currently_playing_track.album_idx]
    next_track : ^Track = nil

    assert(app_state.currently_playing_track != nil)

    // Is last song of the album. Switch to the next one
    if len(current_album.track_indices) - 1 == int(app_state.currently_playing_track.order_nr_in_album) {
        is_last_album := len(app_state.albums) - 1  == int(app_state.currently_playing_track.album_idx)
        if is_last_album {
            app_state.currently_playing_track = nil
            app_state.ma_sound = nil
            app_state.audio_state = .Stopped
            return
        }

        next_track_idx := app_state.albums[app_state.currently_playing_track.album_idx + 1].track_indices[0]
        next_track = &app_state.tracks[next_track_idx]
    } else {
        next_track_idx := current_album.track_indices[app_state.currently_playing_track.order_nr_in_album + 1]
        next_track = &app_state.tracks[next_track_idx]
    }

    ma.sound_uninit(app_state.ma_sound)
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.currently_playing_track = nil

    if next_track != nil {
        app_state.ma_sound = new(ma.sound)
        res := ma.sound_init_from_file(&app_state.ma_engine, next_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
        if res != .SUCCESS {
            app_state.ma_sound = nil
            fmt.println("Could not start the next track")
        } else {
            sound_start_result := ma.sound_start(app_state.ma_sound)
            if sound_start_result == .SUCCESS {
                app_state.audio_state = .Playing
                app_state.currently_playing_track = next_track
            }
        }
    }
}

@private
draw_playlist_list :: proc(app_state: ^App_State) {
    pos_y : f32 = app_state.side_panel_option_content_rect.y

    new_playlist_rect_bounds := rl.Rectangle{
        x = 0,
        y = pos_y,
        width = app_state.side_panel_option_content_rect.width,
        height = SIDE_PANEL_ROW_HEIGHT
    }
    // center text
    txt_measurement := rl.MeasureTextEx(app_state.fonts[20], "+ new playlist", FONT_20, 0)
    //txt_y := ((new_playlist_rect_bounds.height - new_playlist_rect_bounds.y) / 2) + new_playlist_rect_bounds.y

    txt_left_padding : f32 = 20
    rl.DrawTextEx(
        app_state.fonts[FONT_20],
        "+ new playlist",
        {new_playlist_rect_bounds.x + txt_left_padding, pos_y},
        FONT_20, 0, rl.BLACK)

    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_option_content_rect) {
        if rl.CheckCollisionPointRec(rl.GetMousePosition(), new_playlist_rect_bounds) {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                app_state.is_create_playlist_modal_open = true
                app_state.active_viewport = .Create_Playlist_Modal
                // open enter playlist name prompt
                //create_playlist(app_state, "test")
            }
        }
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

        artist_item_bounds := rl.Rectangle{
            x = 0,
            y = pos_y,
            width = app_state.side_panel_option_content_rect.width,
            height = SIDE_PANEL_ROW_HEIGHT
        }

        if artist == app_state.current_selected_artist || (artist == ALL_ARTISTS_OPTION && app_state.current_selected_artist == nil) {
            rl.DrawRectangleRec(artist_item_bounds, rl.LIGHTGRAY)
        }

        // center text
        artist_txt_measurements := rl.MeasureTextEx(app_state.fonts[20], artist, FONT_20, 0)
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
                    // clicked on already active artist => Do nothing
                    if artist == app_state.current_selected_artist do return

                    if artist == ALL_ARTISTS_OPTION {
                        app_state.current_selected_artist = nil
                    } else {
                        app_state.current_selected_artist = artist
                    }
                    app_state.main_panel_scroll_offset = 0
                    app_state.rebuild_rows = true
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
draw_side_panel :: proc(app_state: ^App_State) {
    //rl.DrawRectangleRec(app_state.side_panel_options_rect, rl.ORANGE)
    //rl.DrawRectangleRec(app_state.side_panel_option_content_rect, rl.GREEN)

    // side panel options
    {
        artists_option_bounds := rl.Rectangle{
            x = app_state.side_panel_options_rect.x,
            y = app_state.side_panel_options_rect.y + 20,
            width = app_state.side_panel_options_rect.width,
            height = 25
        }

        // highlight the option
        if app_state.selected_side_panel_option == .Artist_List {
            rl.DrawRectangleRec(artists_option_bounds, rl.ORANGE)
        }

        text_measurement := rl.MeasureTextEx(app_state.fonts[FONT_20], "Artists", FONT_20, 0)
        txt_y := ((artists_option_bounds.height - text_measurement.y) / 2) + artists_option_bounds.y

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Artists",
            {app_state.side_panel_rect.x + 20, txt_y},
            FONT_20,
            0,
            rl.BLACK)

        playlists_option_bounds := rl.Rectangle{
            x = app_state.side_panel_options_rect.x,
            y = app_state.side_panel_options_rect.y + 50,
            width = app_state.side_panel_options_rect.width,
            height = 25
        }

        // highlight the option
        if app_state.selected_side_panel_option == .Playlists {
            rl.DrawRectangleRec(playlists_option_bounds, rl.ORANGE)
        }

        text_measurement = rl.MeasureTextEx(app_state.fonts[FONT_20], "Playlists", FONT_20, 0)
        txt_y = ((playlists_option_bounds.height - text_measurement.y) / 2) + playlists_option_bounds.y
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Playlists",
            {app_state.side_panel_rect.x + 20, txt_y},
            FONT_20,
            0,
            rl.BLACK)

        // handle on options click
        if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_options_rect) {
            if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                if rl.CheckCollisionPointRec(rl.GetMousePosition(), artists_option_bounds) {
                    app_state.selected_side_panel_option = .Artist_List
                } else if rl.CheckCollisionPointRec(rl.GetMousePosition(), playlists_option_bounds) {
                    app_state.selected_side_panel_option = .Playlists
                }
            }
        }
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

    if app_state.selected_side_panel_option == .Artist_List {
        draw_artist_list(app_state)
    } else if app_state.selected_side_panel_option == .Playlists {
        draw_playlist_list(app_state)
    }

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
            draw_album_title_row(app_state, row, &pos_y)
        } else {
            draw_track_list_item(app_state, pos_y, row)
            pos_y += ROW_HEIGHT
        }
    }

    rl.EndScissorMode()

    // Handle main panel scrolling
    wheel := rl.GetMouseWheelMove()
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel_rect) && app_state.active_viewport == .Main {
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

@(private)
draw_insert_library_path_screen :: proc(app_state: ^App_State) {
    rl.DrawText("Set LIBRARY_PATH in ~/.config/music_player/config", 100, 100, FONT_30, rl.BLACK)
}

@(private = "file")
draw_album_title_row :: proc(app_state: ^App_State, row: ^Row, pos_y: ^f32) {
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
        } else { // no cover. Load default placeholder
            rl.DrawTexture(app_state.default_album_cover_texture, i32(app_state.main_panel_rect.x), i32(pos_y^), rl.WHITE)
        }
    }

}


@(private = "file")
draw_track_list_item :: proc(app_state: ^App_State, pos_y: f32, row: ^Row) {
    list_item := rl.Rectangle{
        x = app_state.main_panel_rect.x + TRACK_LIST_OFFSET_X,
        y = pos_y,
        width = app_state.main_panel_rect.width,
        height = ROW_HEIGHT
    }

    // detect track clicked
    if (
        app_state.active_viewport == .Main &&
        rl.CheckCollisionPointRec(rl.GetMousePosition(), list_item) &&
        rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.main_panel_rect)
    ) {
        // highlight
        rl.DrawRectangleRec(list_item, rl.ORANGE)

        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            handle_track_selection(app_state, row.track, row.track_idx)
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
            row.track.album_title,
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

    handle_track_selection :: proc(app_state: ^App_State, selected_track: ^Track, selected_track_idx: Track_Idx) {
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
                app_state.currently_playing_track = selected_track
                app_state.currently_playing_track_idx = selected_track_idx
                build_queue(app_state)
            }
        }
    }
}

@(private = "file")
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

draw_debug_panel :: proc(app_state: ^App_State) {
    bounds := rl.Rectangle{
        x = f32(rl.GetScreenWidth() - 600),
        y = 0,
        height = f32(rl.GetScreenHeight()),
        width = 600
    }

    rl.DrawRectangleRec(bounds, rl.Fade(rl.BLACK, 0.5))

    // @note: no memory allocation because it already exists on stack
    buf: [32]u8
    text := fmt.bprintf(buf[:], "%v", app_state.current_frame_rendered)
    buf[len(text)] = 0
    cstr := cstring(&buf[0])

    rl.DrawTextEx(
        app_state.fonts[FONT_20],
        cstr,
        {bounds.x + 10, 20},
        FONT_20, 0, rl.ORANGE)

    pos_y := 60
    for entry in app_state.album_art_cache.entries {
        if entry == nil do continue

        album := app_state.albums[entry.album_idx]

        buf: [256]u8
        text := fmt.bprintf(buf[:], "ALBUM -> %s; entry_frame: %i", album.title, entry.frame)
        buf[len(text)] = 0
        
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            cstring(&buf[0]),
            {bounds.x + 10, f32(pos_y)},
            FONT_20, 0, rl.ORANGE)

        pos_y += 20
    }
}

// @todo: input field 
draw_create_playlist_modal :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Create_Playlist_Modal)

    rl.DrawRectangleRec(rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.Fade(rl.BLACK, 0.5))

    // @todo: is it ok to do this inside draw?
    app_state.create_playlist_modal_rect = rl.Rectangle{
        x = f32(rl.GetScreenWidth() / 2 - 150),
        y = 200,
        height = 100,
        width = 300
    }
    rl.DrawRectangleRec(app_state.create_playlist_modal_rect, rl.WHITE)

    input_bounds := rl.Rectangle{
        x = app_state.create_playlist_modal_rect.x + (app_state.create_playlist_modal_rect.width / 2) - 100,
        y = app_state.create_playlist_modal_rect.y + 10,
        height = 30,
        width = 200
    }
    rl.DrawRectangleLinesEx(input_bounds, 1, rl.GRAY)
    // @todo: draw the input text
}

@private
update_layout :: proc(app_state: ^App_State) {
    // -40 := 20px padding from left and right
    app_state.main_panel_rect.width = f32(rl.GetScreenWidth() - 40)
    app_state.main_panel_rect.height = f32(rl.GetScreenHeight()) - app_state.playback_controls_panel_rect.height
    app_state.side_panel_rect.height = app_state.main_panel_rect.height + app_state.main_panel_rect.y // @explain
    app_state.side_panel_option_content_rect.height = app_state.side_panel_rect.height - app_state.side_panel_options_rect.height

    app_state.playback_controls_panel_rect.width = f32(rl.GetScreenWidth())
    app_state.playback_controls_panel_rect.y = app_state.main_panel_rect.height
}
