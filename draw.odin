package main

import "core:fmt"
import "core:strings"
import "core:log"
import "core:unicode/utf8"
import rl "vendor:raylib"
import ma "vendor:miniaudio"
import "nfd"

SEARCH_PANEL_ROW_HEIGHT :: 30
CONTENT_MAX_HEIGHT_BUFFER :: 150 // 150 just a random buffer to fix minor calculation mistakes

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
            rl.GRAY
        )
        draw_playback_controls(app_state)

        // Display currently playing track
        {
            if app_state.currently_playing_track != nil {
                cover_texture, found := get_album_cover_texture(app_state, app_state.currently_playing_track.album_idx)
                if found {
                    rl.DrawTextureEx(
                        cover_texture,
                        {BOTTOM_BAR_PADDING, f32(rl.GetScreenHeight() - 125)},
                        0,
                        0.30,
                        rl.WHITE)
                }

                rl.DrawTextEx(
                    app_state.fonts[FONT_18],
                    app_state.currently_playing_track.title,
                    {BOTTOM_BAR_PADDING + 70, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 75)},
                    FONT_18, 0, rl.WHITE)

                rl.DrawTextEx(
                    app_state.fonts[FONT_18],
                    app_state.currently_playing_track.artist,
                    {BOTTOM_BAR_PADDING + 70, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 55)},
                    FONT_18, 0, rl.YELLOW)

                rl.DrawTextEx(
                    app_state.fonts[FONT_18],
                    app_state.currently_playing_track.album_title,
                    {BOTTOM_BAR_PADDING + 70, f32(rl.GetScreenHeight() - BOTTOM_BAR_PADDING - 35)},
                    FONT_18, 0, rl.GRAY)
            }
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
            rl.WHITE)
    } else if app_state.audio_state == .Paused || app_state.audio_state == .Stopped {
        rl.DrawTexture(
            app_state.play_button_texture,
            i32(play_pause_button_bounds.x), i32(play_pause_button_bounds.y),
            rl.WHITE)
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
            rl.WHITE)

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), next_song_button_bounds) {
            if rl.IsMouseButtonPressed(.LEFT) {
                handle_next_track_pick(app_state)
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
            rl.WHITE)

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), prev_song_button_bounds) {
            if rl.IsMouseButtonPressed(.LEFT) {
                handle_prev_song_pick(app_state)
            }
        }
    }

    // shuffle
    {
        button_bounds := rl.Rectangle{
            x = f32(app_state.playback_controls_panel_rect.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) - 100,
            y = f32(rl.GetScreenHeight() - 110),
            width = 50,
            height = 50
        }

        if app_state.is_shuffle_play {
            rl.DrawTexture(
                app_state.shuffle_on_button_texture,
                i32(button_bounds.x), i32(button_bounds.y),
                rl.WHITE)
        } else {
            rl.DrawTexture(
                app_state.shuffle_off_button_texture,
                i32(button_bounds.x), i32(button_bounds.y),
                rl.WHITE)
        }

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), button_bounds) {
            if rl.IsMouseButtonPressed(.LEFT) {
                handle_shuffle_pressed(app_state)
            }
        }
    }

    // repeat
    {
        button_bounds := rl.Rectangle{
            x = f32(app_state.playback_controls_panel_rect.width / 2) - (PLAYBACK_BUTTON_SIZE / 2) + 100,
            y = f32(rl.GetScreenHeight() - 110),
            width = 50,
            height = 50
        }

        if app_state.playback_mode == .Normal {
            rl.DrawTexture(
                app_state.repeat_button_texture,
                i32(button_bounds.x), i32(button_bounds.y),
                rl.WHITE)
        } else if app_state.playback_mode == .Repeat_Queue {
            rl.DrawTexture(
                app_state.repeat_queue_button_texture,
                i32(button_bounds.x), i32(button_bounds.y),
                rl.WHITE)
        } else if app_state.playback_mode == .Repeat_One {
            rl.DrawTexture(
                app_state.repeat_one_button_texture,
                i32(button_bounds.x), i32(button_bounds.y),
                rl.WHITE)
        }


        if rl.CheckCollisionPointRec(rl.GetMousePosition(), button_bounds) {
            if rl.IsMouseButtonPressed(.LEFT) {
                handle_repeat_pressed(app_state)
            }
        }
    }

}

@private
handle_repeat_pressed :: proc(app_state: ^App_State) {
    current_mode := app_state.playback_mode

    #partial switch current_mode {
    case .Normal: app_state.playback_mode = .Repeat_Queue
    case .Repeat_Queue: app_state.playback_mode = .Repeat_One
    case .Repeat_One: app_state.playback_mode = .Normal
    }
}

handle_shuffle_pressed :: proc(app_state: ^App_State) {
    app_state.is_shuffle_play = !app_state.is_shuffle_play

    if app_state.is_shuffle_play {
        shuffle_queue(app_state)
    } else {
        app_state.rebuild_queue = true
    }
}

@private
handle_play_pause :: proc(app_state: ^App_State) {
    if app_state.audio_state == .Playing {
        stop_response := ma.sound_stop(app_state.ma_sound)
        if stop_response == .SUCCESS {
            app_state.audio_state = .Paused
        } else {
            log.errorf("ma.sound_stop failed: %v", stop_response)
        }
    } else if app_state.audio_state == .Paused && app_state.ma_sound != nil {
        start_response := ma.sound_start(app_state.ma_sound)
        if start_response == .SUCCESS {
            app_state.audio_state = .Playing
        } else {
            log.errorf("ma.sound_start failed: %v", start_response)
        }
    }
}

handle_prev_song_pick :: proc(app_state: ^App_State) -> bool {
    if app_state.current_position_in_queue == 0 do return false

    app_state.current_position_in_queue -= 1
    prev_track := app_state.queue[app_state.current_position_in_queue]

    reset_player(app_state)

    app_state.ma_sound = new(ma.sound)
    res := ma.sound_init_from_file(&app_state.ma_engine, prev_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
    if res != .SUCCESS {
        app_state.ma_sound = nil
        log.errorf("ma.sound_init_from_file failed: %v", res)
        return false
    } else {
        sound_start_result := ma.sound_start(app_state.ma_sound)
        if sound_start_result == .SUCCESS {
            app_state.audio_state = .Playing
            app_state.currently_playing_track = prev_track
        }
    }

    return true
}

@private
handle_next_track_pick :: proc(app_state: ^App_State) -> bool {
    // do not allow to pick a next track if there is no current track playing
    // or if the player is in a Stopped state
    if app_state.currently_playing_track == nil || app_state.audio_state == .Stopped {
        return false
    }

    queue_len := i32(len(app_state.queue))
    if queue_len == 0 {
        return false
    }

    if app_state.current_position_in_queue == queue_len - 1 {
        if app_state.playback_mode == .Repeat_Queue {
            // move back to the start of the queue
            app_state.current_position_in_queue = 0
        } else {
            // reached end of the queue
            return false
        }
    } else {
        // continue the queue
        app_state.current_position_in_queue += 1
    }

    next_track := app_state.queue[app_state.current_position_in_queue]

    reset_player(app_state)

    app_state.ma_sound = new(ma.sound)
    res := ma.sound_init_from_file(&app_state.ma_engine, next_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
    if res != .SUCCESS {
        log.errorf("ma.sound_init_from_file failed: %v", res)
        reset_player(app_state)
        return false
    } else {
        sound_start_result := ma.sound_start(app_state.ma_sound)
        if sound_start_result == .SUCCESS {
            app_state.audio_state = .Playing
            app_state.currently_playing_track = next_track
        } else {
            return false
        }
    }

    return true
}

// @todo
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
    pos_y : f32 = app_state.side_panel_option_content_rect.y
    end_y := app_state.side_panel_option_content_rect.height + app_state.side_panel_option_content_rect.y

    start := i32(app_state.side_panel_scroll_offset / SIDE_PANEL_ROW_HEIGHT)
    assert(start >= 0)

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

        artist_txt_color := rl.LIGHTGRAY
        if artist == app_state.current_selected_artist || (artist == ALL_ARTISTS_OPTION && app_state.current_selected_artist == nil) {
            rl.DrawRectangleRec(artist_item_bounds, rl.GRAY)
            artist_txt_color = rl.WHITE
        }

        // center text
        txt_y := center_text_y(app_state.fonts[FONT_20], artist_item_bounds)

        txt_left_padding : f32 = 20
        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            artist,
            {artist_item_bounds.x + txt_left_padding, txt_y},
            FONT_20, 0, artist_txt_color)

        pos_y += artist_item_bounds.height

        if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_option_content_rect) && app_state.active_viewport == .Main {
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), artist_item_bounds) {
                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    // clicked on already active artist => Do nothing
                    if artist == app_state.current_selected_artist do continue

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
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.side_panel_option_content_rect) && app_state.active_viewport == .Main {
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
            height = ROW_HEIGHT
        }

        // highlight the option
        if app_state.selected_side_panel_option == .Artist_List {
            rl.DrawRectangleRec(artists_option_bounds, rl.ORANGE)
        }

        txt_y := center_text_y(app_state.fonts[FONT_20], artists_option_bounds)

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Artists",
            {app_state.side_panel_rect.x + 20, txt_y},
            FONT_20,
            0,
            rl.WHITE)

        playlists_option_bounds := rl.Rectangle{
            x = app_state.side_panel_options_rect.x,
            y = app_state.side_panel_options_rect.y + 50,
            width = app_state.side_panel_options_rect.width,
            height = ROW_HEIGHT
        }

        // highlight the option
        if app_state.selected_side_panel_option == .Playlists {
            rl.DrawRectangleRec(playlists_option_bounds, rl.ORANGE)
        }

        txt_y = center_text_y(app_state.fonts[FONT_20], playlists_option_bounds)

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            "Playlists",
            {app_state.side_panel_rect.x + 20, txt_y},
            FONT_20,
            0,
            rl.WHITE)

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
        rl.GRAY)


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
        rl.GRAY
    )
}

@(private = "file")
draw_main_panel_content :: proc(app_state: ^App_State) {
    if len(app_state.rows) == 0 do return

    rl.BeginScissorMode(
        i32(app_state.main_panel_rect.x),
        i32(app_state.main_panel_rect.y),
        i32(app_state.main_panel_rect.width),
        i32(app_state.main_panel_rect.height))

    pos_y := app_state.main_panel_rect.y


    start := i32(app_state.main_panel_scroll_offset / ROW_HEIGHT)
    assert(start >= 0)

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

        if row.is_album_title_row {
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
            if app_state.main_panel_scroll_offset + i32(app_state.main_panel_rect.height) < app_state.content_max_height + CONTENT_MAX_HEIGHT_BUFFER {
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

    // @todo: main panel scroll bar
    // have to redo the main panel scrolling and the list view drawing
    /*{
        if f32(app_state.content_max_height + 150) > app_state.main_panel_rect.height {
            x := i32(app_state.main_panel_rect.height) * 100 / (app_state.content_max_height + CONTENT_MAX_HEIGHT_BUFFER)
            scoll_bar_height := i32(app_state.main_panel_rect.height) * x / 100
            scroll_bar_offset := f32(app_state.main_panel_scroll_offset) / f32(app_state.content_max_height + CONTENT_MAX_HEIGHT_BUFFER) * app_state.main_panel_rect.height

            app_state.main_panel_scroll_bar_rect = rl.Rectangle{
                x = f32(rl.GetScreenWidth() - 10),
                y = scroll_bar_offset,
                height = f32(scoll_bar_height),
                width = 5
            }

            rl.DrawRectangleRec(app_state.main_panel_scroll_bar_rect, rl.GRAY)
        }
    }*/

}

@(private = "file")
draw_album_title_row :: proc(app_state: ^App_State, row: ^Row, pos_y: ^f32) {
    album := app_state.albums[row.album_idx]

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
        rl.WHITE)

    rl.DrawLine(
        i32(text_measurement.x + app_state.main_panel_rect.x + 20), 
        i32(pos_y^ + FONT_30 / 2),
        i32(app_state.main_panel_rect.width),
        i32(pos_y^ + FONT_30 / 2),
        rl.GRAY)

    pos_y^ += ROW_HEIGHT

    cover_texture, found := get_album_cover_texture(app_state, row.album_idx)
    if found {
        rl.DrawTexture(cover_texture, i32(app_state.main_panel_rect.x), i32(pos_y^), rl.WHITE)
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
            handle_track_selection(app_state, row.track)
        }
    }

    txt_y := center_text_y(app_state.fonts[FONT_20], list_item)

    txt_color := rl.LIGHTGRAY
    is_playing := app_state.currently_playing_track != nil && row.track.file_path == app_state.currently_playing_track.file_path
    if is_playing {
        txt_color = rl.YELLOW
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

    handle_track_selection :: proc(app_state: ^App_State, selected_track: ^Track) {
        if app_state.ma_sound != nil {
            ma.sound_uninit(app_state.ma_sound)
            app_state.ma_sound = nil
        }

        app_state.ma_sound = new(ma.sound)
        res := ma.sound_init_from_file(&app_state.ma_engine, selected_track.file_path, {.STREAM}, nil, nil, app_state.ma_sound)
        if res != .SUCCESS {
            app_state.ma_sound = nil
            log.errorf(
                "ma.sound_init_from_file failed: %v. FilePath: %s", 
                res, selected_track.file_path
            )
        } else {
            sound_start_result := ma.sound_start(app_state.ma_sound)
            if sound_start_result == .SUCCESS {
                app_state.audio_state = .Playing
                app_state.currently_playing_track = selected_track
                app_state.rebuild_queue = true
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
        0, 2, rl.RAYWHITE)
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

draw_search_panel :: proc(app_state: ^App_State) {
    // panel body
    {
        rl.DrawRectangleRounded(rl.Rectangle{
            f32(rl.GetScreenWidth() / 2 - 500) - 2.5,
            200 - 2.5,
            1005, 1005}, 0.03, 0, rl.Fade(rl.GRAY, 0.5))

        app_state.search_panel_rect = rl.Rectangle{
            x = f32(rl.GetScreenWidth() / 2 - 500),
            y = 200,
            height = 1000,
            width = 1000
        }

        rl.DrawRectangleRounded(app_state.search_panel_rect, 0.03, 0, rl.BLACK)
    }

    // input
    {
        INPUT_X_OFFSET :: 60
        INPUT_Y_OFFSET :: 20

        rl.DrawTexture(
            app_state.search_logo_texture,
            i32(app_state.search_panel_rect.x + 20), i32(app_state.search_panel_rect.y + 15),
            rl.WHITE)

        input := utf8.runes_to_string(app_state.search_input[:], context.temp_allocator)
        cinput := fmt.ctprintf("%s", app_state.search_input)

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            cinput,
            {app_state.search_panel_rect.x + INPUT_X_OFFSET, app_state.search_panel_rect.y + INPUT_Y_OFFSET},
            FONT_20, 0, rl.WHITE)

        // input caret
        {
            app_state.search_panel.caret.rect = rl.Rectangle{
                x = app_state.search_panel_rect.x + INPUT_X_OFFSET + app_state.search_panel.caret.pos.x, 
                y = app_state.search_panel_rect.y + INPUT_Y_OFFSET,
                height = 20,
                width = 2
            }

            rl.DrawRectangleRec(app_state.search_panel.caret.rect, rl.WHITE)
        }

        rl.DrawLineEx(
            {app_state.search_panel_rect.x, app_state.search_panel_rect.y + 60},
            {app_state.search_panel_rect.x + app_state.search_panel_rect.width, app_state.search_panel_rect.y + 60},
            1.0,
            rl.GRAY)
    }

    rl.BeginScissorMode(
        i32(app_state.search_panel_rect.x),
        i32(app_state.search_panel_rect.y),
        i32(app_state.search_panel_rect.width),
        i32(app_state.search_panel_rect.height))

    // search results
    {
        search_result_offset_y :: 70

        search_content_height := app_state.search_panel_rect.height - search_result_offset_y
        total_possible_rows_to_render := i32(search_content_height / SEARCH_PANEL_ROW_HEIGHT)
        last_row_visible := i32(len(app_state.search_results)) < total_possible_rows_to_render ? i32(len(app_state.search_results)) : total_possible_rows_to_render

        if last_row_visible < i32(len(app_state.search_results)) {
            last_row_visible += app_state.search_panel_scroll_index
        }

        if len(app_state.search_results) > 0 {
            wheel := rl.GetMouseWheelMove()
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.search_panel_rect){
                if wheel < 0 { // scroll down
                    if i32(len(app_state.search_results)) > last_row_visible {
                        app_state.search_panel_scroll_index += 1
                    }
                } else if wheel > 0 {
                    if app_state.search_panel_scroll_index > 0 {
                        app_state.search_panel_scroll_index -= 1
                    }
                }
            }
        }

        // @todo: draw commands
        y := app_state.search_panel_rect.y + search_result_offset_y
        for value in app_state.search_results[app_state.search_panel_scroll_index:last_row_visible] {
            bounds := rl.Rectangle{app_state.search_panel_rect.x, y, app_state.search_panel_rect.width, 30}

            if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
                // highlight
                rl.DrawRectangleRec(bounds, rl.ORANGE)

                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    if value.type == .Artist {
                        if value.artist_name == app_state.current_selected_artist do continue
                            if value.artist_name == ALL_ARTISTS_OPTION {
                                app_state.current_selected_artist = nil
                            } else {
                                app_state.current_selected_artist = value.artist_name
                            }
                            app_state.main_panel_scroll_offset = 0
                            app_state.rebuild_rows = true
                    } else if value.type == .Album {
                        if value.album.artist == app_state.current_selected_artist do continue
                            app_state.current_selected_artist = value.album.artist
                            app_state.main_panel_scroll_offset = 0
                            app_state.rebuild_rows = true
                    } else if value.type == .Command {
                        if value.cmd == .Set_Library {
                            out_path : cstring
                            res := nfd.PickFolderN(&out_path, "$HOME/Music")
                            if res == .Okay {
                                app_state.library_path = strings.clone_to_cstring(string(out_path))
                                app_state.is_library_path_set = true
                                app_state.rescan_library = true
                            }
                        }
                    }
                    close_search_panel(app_state)
                }
            }

            txt_y := center_text_y(app_state.fonts[FONT_20], bounds)

            if value.type == .Artist {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "ARTIST",
                    {app_state.search_panel_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    value.artist_name,
                    {app_state.search_panel_rect.x + 100, txt_y},
                    FONT_20, 0, rl.WHITE)
            } else if value.type == .Album {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "ALBUM",
                    {app_state.search_panel_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    value.album.title,
                    {app_state.search_panel_rect.x + 100, txt_y},
                    FONT_20, 0, rl.WHITE)
            } else if value.type == .Command {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "CMD",
                    {app_state.search_panel_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    COMMANDS[value.cmd],
                    {app_state.search_panel_rect.x + 100, txt_y},
                    FONT_20, 0, rl.WHITE)
            }

            y += SEARCH_PANEL_ROW_HEIGHT
        }
    }

    rl.EndScissorMode()
}

center_text_y :: proc(font: rl.Font, bounds: rl.Rectangle) -> f32 {
    text_measurement := rl.MeasureTextEx(font, "test", f32(font.baseSize), 0)
    txt_y := ((bounds.height - text_measurement.y) / 2) + bounds.y
    return txt_y
}

// @todo: input field 
draw_create_playlist_modal :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Create_Playlist_Modal)

    rl.DrawRectangleRec(rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.Fade(rl.LIGHTGRAY, 0.5))

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

