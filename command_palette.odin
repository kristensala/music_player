package main

import "core:sort"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"
import "nfd"

Command_Palette :: struct {
    caret: Caret,
    command_palette_rect: rl.Rectangle,

    command_palette_input: [dynamic]rune,
    search_results: [dynamic]Search_Result_Row,

    command_palette_scroll_index: i32
}

// @testing: Damerau-Levenshtein distance
min_distance :: proc(s1: string, s2: string) -> int {
    if len(s2) < len(s1) do return -1

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

    return dp[(rows - 1) * cols + (cols - 1)]
}

similarity :: proc(s1: string, s2: string) -> f64 {
    x := max(len(s1), len(s2))
    if x == 0 do return 1.0
    return 1.0 - f64(min_distance(s1, s2)) / f64(x)
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
    if input[0] == '/' {
        for cmd in COMMANDS {
            result_row := Search_Result_Row{
                type = .Command,
                cmd = cmd
            }

            append(&results, result_row)
        }
    } else {
        for it in app_state.artist_list {
            it_lower := strings.to_lower(string(it), context.temp_allocator)

            d := similarity(input_lower, it_lower)
            contains := strings.contains(it_lower, input_lower)
            if (d >= 0.4 && d <= 1) || contains {
                if contains {
                    d += 0.3
                }

                result_row := Search_Result_Row{
                    type = .Artist,
                    artist_name = it,
                    weight = d
                }

                append(&results, result_row)
            }

        }

        for &it in app_state.albums {
            album_title_lower := strings.to_lower(string(it.title), context.temp_allocator)

            d := similarity(input_lower, album_title_lower)
            contains := strings.contains(album_title_lower, input_lower)
            if (d >= 0.4 && d <= 1) || contains {
                if contains {
                    d += 0.3
                }

                result_row := Search_Result_Row{
                    type = .Album,
                    album = &it,
                    weight = d
                }

                // @todo
                // if artist and album title match
                // key should be artist_{value}
                // key should be album_{album_title}_{artist}
                // key should be track_{track_name}_{artist}
                //app_state.search_results[it.title] = result_row
                append(&results, result_row)
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

close_command_palette :: proc(app_state: ^App_State) {
    app_state.active_viewport = .Main
    app_state.command_palette_scroll_index = 0
    app_state.command_palette.caret.col_idx = 0
    app_state.command_palette.caret.pos.x = 0

    clear(&app_state.command_palette_input)
    clear(&app_state.search_results)
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
                        if value.artist_name == app_state.current_selected_artist do continue
                            if value.artist_name == ALL_ARTISTS_OPTION {
                                app_state.current_selected_artist = nil
                            } else {
                                app_state.current_selected_artist = value.artist_name
                            }
                            app_state.rebuild_rows = true
                    } else if value.type == .Album {
                        if value.album.artist == app_state.current_selected_artist do continue
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
