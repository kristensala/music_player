package main

import "core:fmt"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"
import "nfd"

Command_Palette :: struct {
    caret: Caret,
    command_palette_rect: rl.Rectangle,

    command_palette_input: [dynamic]rune,
    search_results: [dynamic]Search_Result_Row,

    album_trigram_inverted_index: map[string][dynamic]i32,
    artist_trigram_inverted_index: map[string][dynamic]i32,
    //track_trigram_inverted_index: map[string][dynamic]i32,

    command_palette_scroll_index: i32
}

// Damerau-Levenshtein distance
measure_string_distance :: proc(s1: string, s2: string) -> int {
    rows := len(s1) + 1
    cols := len(s2) + 1

    dp := make([]int, rows*cols)
    defer delete(dp)

    for i := 0; i <= len(s1); i+=1 {
        dp[i * cols] = i
    }

    for j := 0; j <= len(s2); j+=1 {
        dp[j] = j
    }

    for i := 1; i <= len(s1); i+=1 {
        for j := 1; j <= len(s2); j+=1 {
            if s1[i-1] == s2[j-1] {
                dp[i * cols + j] = dp[(i - 1) * cols + (j - 1)]
            } else {
                // dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                dp[i * cols + j] = 1 + min(dp[(i - 1) * cols + j], dp[i * cols + (j - 1)], dp[(i - 1) * cols + (j - 1)])
            }
        }
    }

    distance := dp[(rows - 1) * cols + (cols - 1)]
    return distance
}

similarity :: proc(s1: string, s2: string) -> f64 {
    x := max(len(s1), len(s2))
    if x == 0 do return 1.0
    return 1.0 - f64(measure_string_distance(s1, s2)) / f64(x)
}

update_search_results :: proc(app_state: ^App_State) {
    input := utf8.runes_to_string(app_state.command_palette_input[:], context.temp_allocator)

    if len(input) == 0 {
        clear(&app_state.search_results)
        return
    }

    results : [dynamic]Search_Result_Row
    defer delete(results)

    input_lower := strings.to_lower(input, context.temp_allocator)

    input_as_trigram : [dynamic]string
    defer delete(input_as_trigram)

    if len(input) == 3 {
        append(&input_as_trigram, input_lower)
    }

    for i := 0; i < len(input_lower); i += 1 {
        end := i + 3
        if len(input_lower) <= 3 {
            end = i + 2
        }

        if end > len(input_lower) {
            break
        }
        append(&input_as_trigram, input_lower[i:end])
    }

    if input[0] == '/' {
        for cmd in COMMANDS {
            result_row := Search_Result_Row{
                type = .Command,
                cmd = cmd
            }

            append(&results, result_row)
        }
    } else {
        for it in input_as_trigram {
            artist_indices, found := app_state.command_palette.artist_trigram_inverted_index[it]
            if found {
                for artist_idx in artist_indices {
                    artist := app_state.artist_list[artist_idx]

                    result_exists := false
                    for row in results[:] {
                        if row.type == .Artist && row.artist_name == artist {
                            result_exists = true
                            break
                        }
                    }

                    if result_exists do continue

                    artist_lower := strings.to_lower(string(artist))
                    defer delete(artist_lower)

                    score := similarity(input_lower, artist_lower)
                    if score == 0 do continue

                    result_row := Search_Result_Row{
                        type = .Artist,
                        artist_name = artist,
                        weight = score
                    }
                    append(&results, result_row)
                }
            }

            album_indices, found_album := app_state.command_palette.album_trigram_inverted_index[it]
            if found_album {
                for album_idx in album_indices {
                    album := &app_state.albums[album_idx]
                    if album == nil do continue

                    result_exists := false
                    for row in results[:] {
                        if row.type == .Album && row.album.title == album.title {
                            result_exists = true
                            break
                        }
                    }

                    if result_exists do continue

                    album_title_lower := strings.to_lower(string(album.title))
                    defer delete(album_title_lower)

                    score := similarity(input_lower, album_title_lower)
                    if score == 0 do continue

                    result_row := Search_Result_Row{
                        type = .Album,
                        album = album,
                        weight = score
                    }
                    append(&results, result_row)
                }
            }
        }
    }

    sort.quick_sort_proc(results[:], proc(a, b: Search_Result_Row) -> int {
        if a.weight < b.weight do return 1
        if a.weight > b.weight do return -1
        return 0
    })

    clear(&app_state.search_results)
    append(&app_state.search_results, ..results[:])
}

build_album_trigram_inverted_index :: proc(data: [dynamic]Album) -> map[string][dynamic]i32 {
    trigram_index : map[string][dynamic]i32

    for album, idx in data {
        x := album.title

        build_trigram_from_string_and_add_to_index(&trigram_index, string(x), i32(idx))
    }
    return trigram_index
}

build_trigram_inverted_index :: proc(data: [dynamic]cstring) -> map[string][dynamic]i32 {
    trigram_index : map[string][dynamic]i32

    for x, idx in data {
        build_trigram_from_string_and_add_to_index(&trigram_index, string(x), i32(idx))
    }

    return trigram_index
}

@(private = "file")
build_trigram_from_string_and_add_to_index :: proc(trigram_index: ^map[string][dynamic]i32, input: string, input_idx: i32) {
    for i := 0; i < len(input); i += 1 {
        end := i + 3
        if len(input) <= 3 {
            end = i + 2
        }

        if end > len(input) {
            break
        }

        trigram := strings.to_lower(input[i:end])

        track_idx_array, trigram_exists := trigram_index[trigram]
        if trigram_exists {
            append(&track_idx_array, i32(input_idx))
            trigram_index[trigram] = track_idx_array
        } else {
            array := make([dynamic]i32)
            append(&array, i32(input_idx))
            trigram_index[trigram] = array
        }
    }

    // if word length is 3 add the whole word into index
    if len(input) == 3 {
        trigram := strings.to_lower(input)
        track_idx_array, trigram_exists := trigram_index[trigram]
        if trigram_exists {
            append(&track_idx_array, i32(input_idx))
            trigram_index[trigram] = track_idx_array
        } else {
            array := make([dynamic]i32)
            append(&array, i32(input_idx))
            trigram_index[trigram] = array
        }
    }
}

close_command_palette :: proc(app_state: ^App_State) {
    app_state.active_viewport = .Main
    app_state.command_palette_scroll_index = 0
    app_state.command_palette.caret.col_idx = 0
    app_state.command_palette.caret.pos.x = 0

    clear(&app_state.command_palette.command_palette_input)
    clear(&app_state.command_palette.search_results)
}

handle_command_palette_keyboard_events :: proc(app_state: ^App_State) {
    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
        close_command_palette(app_state)
    }

    if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
        app_state.command_palette_scroll_index = 0

        if len(app_state.command_palette_input) > 0 {
            pop(&app_state.command_palette_input)

            // update caret position
            {
                input := utf8.runes_to_string(app_state.command_palette_input[:])
                cinput := strings.clone_to_cstring(input)
                text_measurement := rl.MeasureTextEx(app_state.fonts[FONT_20], cinput, FONT_20, 0)
                delete(cinput)
                delete(input)

                app_state.command_palette.caret.pos.x = text_measurement.x
                app_state.command_palette.caret.col_idx -= 1
            }
        }
        update_search_results(app_state)
    }

    // @todo: ignore case and move cursor and insert at cursor position
    // ability to navigate in results with arrow keys
    input := rl.GetCharPressed()
    if input > 0 {
        app_state.command_palette_scroll_index = 0

        // update caret position
        {
            app_state.command_palette.caret.col_idx += 1
            glyph_info := rl.GetGlyphInfo(app_state.fonts[FONT_20], input)
            app_state.command_palette.caret.pos.x += f32(glyph_info.advanceX)
        }

        append(&app_state.command_palette_input, input)
        if len(app_state.command_palette_input) == 0 do return

        update_search_results(app_state)
    }
}

draw_command_palette :: proc(app_state: ^App_State) {
    // panel body
    {
        width :: 1000
        width2 :: 1005
        max_height :: 1000
        min_height :: 300

        panel_height := f32(rl.GetScreenHeight()) / 2
        if panel_height > max_height {
            panel_height = max_height
        } else if (panel_height < min_height) {
            panel_height = min_height
        }

        rl.DrawRectangleRec(
            rl.Rectangle{
                f32(rl.GetScreenWidth() / 2 - (width2 / 2)),
                200 - 2.5,
                width2, 
                panel_height + 5
            }, rl.Fade(rl.BLACK, 0.5))

        app_state.command_palette_rect = rl.Rectangle{
            x = f32(rl.GetScreenWidth() / 2 - (width / 2)),
            y = 200,
            height = panel_height,
            width = width
        }

        rl.DrawRectangleRec(app_state.command_palette_rect, rl.WHITE)
    }

    // input
    {
        INPUT_X_OFFSET :: 60
        INPUT_Y_OFFSET :: 20

        rl.DrawTexture(
            app_state.search_logo_texture,
            i32(app_state.command_palette_rect.x + 20), i32(app_state.command_palette_rect.y + 15),
            rl.WHITE)

        input := utf8.runes_to_string(app_state.command_palette_input[:], context.temp_allocator)
        cinput := fmt.ctprintf("%s", app_state.command_palette_input)

        // Input placeholder
        if len(input) == 0 {
            rl.DrawTextEx(
                app_state.fonts[FONT_20],
                "Search or type '/' for commands",
                {app_state.command_palette_rect.x + INPUT_X_OFFSET, app_state.command_palette_rect.y + INPUT_Y_OFFSET},
                FONT_20, 0, rl.DARKGRAY)
        }

        rl.DrawTextEx(
            app_state.fonts[FONT_20],
            cinput,
            {app_state.command_palette_rect.x + INPUT_X_OFFSET, app_state.command_palette_rect.y + INPUT_Y_OFFSET},
            FONT_20, 0, TEXT_COLOR)

        // input caret
        {
            app_state.command_palette.caret.rect = rl.Rectangle{
                x = app_state.command_palette_rect.x + INPUT_X_OFFSET + app_state.command_palette.caret.pos.x, 
                y = app_state.command_palette_rect.y + INPUT_Y_OFFSET,
                height = 20,
                width = 2
            }

            rl.DrawRectangleRec(app_state.command_palette.caret.rect, rl.BLACK)
        }

        rl.DrawLineEx(
            {app_state.command_palette_rect.x, app_state.command_palette_rect.y + 60},
            {app_state.command_palette_rect.x + app_state.command_palette_rect.width, app_state.command_palette_rect.y + 60},
            1.0,
            rl.BLACK)
    }

    rl.BeginScissorMode(
        i32(app_state.command_palette_rect.x),
        i32(app_state.command_palette_rect.y),
        i32(app_state.command_palette_rect.width),
        i32(app_state.command_palette_rect.height))

    // search results
    {
        search_result_offset_y :: 70

        search_content_height := app_state.command_palette_rect.height - search_result_offset_y
        total_possible_rows_to_render := i32(search_content_height / SEARCH_PANEL_ROW_HEIGHT)
        last_row_visible := i32(len(app_state.search_results)) < total_possible_rows_to_render ? i32(len(app_state.search_results)) : total_possible_rows_to_render

        if last_row_visible < i32(len(app_state.search_results)) {
            last_row_visible += app_state.command_palette_scroll_index
        }

        if len(app_state.search_results) > 0 {
            wheel := rl.GetMouseWheelMove()
            if rl.CheckCollisionPointRec(rl.GetMousePosition(), app_state.command_palette_rect){
                if wheel < 0 { // scroll down
                    if i32(len(app_state.search_results)) > last_row_visible {
                        app_state.command_palette_scroll_index += 1
                    }
                } else if wheel > 0 {
                    if app_state.command_palette_scroll_index > 0 {
                        app_state.command_palette_scroll_index -= 1
                    }
                }
            }
        }

        y := app_state.command_palette_rect.y + search_result_offset_y
        for value in app_state.search_results[app_state.command_palette_scroll_index:last_row_visible] {
            bounds := rl.Rectangle{app_state.command_palette_rect.x, y, app_state.command_palette_rect.width, 30}

            if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
                // highlight
                rl.DrawRectangleRec(bounds, HIGHLIGHT_COLOR)

                if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
                    if value.type == .Artist {
                        if string(value.artist_name) == string(app_state.current_selected_artist) {
                            close_command_palette(app_state)
                            return
                        }

                        if value.artist_name == ALL_ARTISTS_OPTION {
                            app_state.current_selected_artist = nil
                        } else {
                            app_state.current_selected_artist = value.artist_name
                        }
                        app_state.rebuild_rows = true

                    } else if value.type == .Album {
                        if value.album.artist == app_state.current_selected_artist {
                            close_command_palette(app_state)
                            return
                        }

                        app_state.current_selected_artist = value.album.artist
                        app_state.rebuild_rows = true
                    } else if value.type == .Command {
                        if value.cmd == .Set_Library {
                            // library path change
                            out_path : cstring
                            res := nfd.PickFolderU8(&out_path, "")
                            if res == .Okay {
                                app_state.library_path = strings.clone_to_cstring(string(out_path))
                                // @todo: this blocks drawing -> should not block
                                nfd.FreePathN(out_path)

                                app_state.is_library_path_set = true
                                app_state.rescan_library = true
                            }
                        }
                    }
                    close_command_palette(app_state)
                }
            }

            txt_y := center_text_y(app_state.fonts[FONT_20], bounds)

            if value.type == .Artist {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "ARTIST",
                    {app_state.command_palette_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    value.artist_name,
                    {app_state.command_palette_rect.x + 100, txt_y},
                    FONT_20, 0, TEXT_COLOR)

                // @temp: remove later
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    fmt.ctprintf("%f", value.weight),
                    {app_state.command_palette_rect.x + 500, txt_y},
                    FONT_20, 0, rl.GRAY)
            } else if value.type == .Album {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "ALBUM",
                    {app_state.command_palette_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    value.album.title,
                    {app_state.command_palette_rect.x + 100, txt_y},
                    FONT_20, 0, TEXT_COLOR)

                // @temp: remove later
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    fmt.ctprintf("%f", value.weight),
                    {app_state.command_palette_rect.x + 500, txt_y},
                    FONT_20, 0, rl.GRAY)
            } else if value.type == .Command {
                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    "CMD",
                    {app_state.command_palette_rect.x + 20, txt_y},
                    FONT_20, 0, rl.GRAY)

                rl.DrawTextEx(
                    app_state.fonts[FONT_20],
                    COMMANDS[value.cmd],
                    {app_state.command_palette_rect.x + 100, txt_y},
                    FONT_20, 0, TEXT_COLOR)
            }

            y += SEARCH_PANEL_ROW_HEIGHT
        }
    }

    rl.EndScissorMode()
}
