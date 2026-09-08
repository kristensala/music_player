/*
   @todo: Inactive feature
*/
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:strconv"
import "core:sort"
import rl "vendor:raylib"

Playlist :: struct {
    title: string,
    file_name: string, // path is always library_path/.mppl/{file_name}
    playlist_file_path: string,
    tracks: [dynamic]^Track,
}

Create_Playlist_Modal :: struct {
    create_playlist_modal_rect: rl.Rectangle,
    create_playlist_modal_input: [dynamic]rune,

    is_create_playlist_modal_open: bool
}

init_playlists_from_playlist_files :: proc(app_state: ^App_State) {
    playlist_files, err := os.read_directory_by_path(app_state.playlist_path, 0, context.allocator)
    if err != nil {
        fmt.eprintln(#procedure, "Failed to read the playlist directory by path: ", err)
        return
    }
    defer delete(playlist_files)

    for f in playlist_files {
        file_data, err := os.read_entire_file_from_path(f.fullpath, context.allocator)
        if err != nil {
            fmt.eprintln(#procedure, "Failed to read the playlist file: ", err)
            continue
        }
        defer delete(file_data)

        if len(file_data) == 0 do continue

        current_playlist := Playlist{
            playlist_file_path = f.fullpath
        }

        line_idx := 0
        it := string(file_data)
        for line in strings.split_lines_iterator(&it) {
            if line_idx == 0 {
                current_playlist.title = line
            } else {
                track_full_path, err := filepath.join({string(app_state.library_path), line}, context.allocator)
                if err != nil {
                    fmt.eprintln(#procedure, "Failed to join library path with the path from playlist file: ", err)
                    line_idx += 1
                    continue
                }
                defer delete(track_full_path)

                for &track in app_state.tracks {
                    if strings.compare(string(track.file_path), track_full_path) == 0 {
                        append(&current_playlist.tracks, &track)
                        break
                    }
                }
            }
            line_idx += 1
        }

        append(&app_state.playlists, current_playlist)
    }
}

// @todo: testing
create_playlist :: proc(app_state: ^App_State, playlist_name: string) {
    err := get_or_create_playlist_dir(app_state.playlist_path)
    if err != nil {
        fmt.eprintln("Could not create or read playlist path: ", err)
        return
    }

    files, dir_read_err := os.read_directory_by_path(app_state.playlist_path, 0, context.allocator)
    if dir_read_err != nil {
        fmt.eprintln(#procedure, "Could not create the playlist: ", dir_read_err)
        return
    }
    defer delete(files)

    next_file_name : string = "mppl0"
    if len(files) > 0 {
        sort.quick_sort_proc(files, proc(a, b: os.File_Info) -> int {
            if a.name < b.name do return -1
            if a.name > b.name do return 1
            return 0
        })

        current_file_name := files[len(files) - 1].name
        current_playlist_nr := current_file_name[len("mppl"):]

        // @todo: if unable to parse, get the second last file and so on
        current_playlist_nr_int, ok := strconv.parse_int(current_playlist_nr)
        assert(ok == true)

        next_file_name = fmt.tprintf("mppl%i", current_playlist_nr_int + 1)
    }

    // @todo: handle error
    file_path, e := filepath.join({app_state.playlist_path, next_file_name}, context.allocator)
    defer delete(file_path)

    playlist_file, file_create_err := os.create(file_path)
    if file_create_err != nil {
        fmt.eprintln(#procedure, "Could not create a playlist file: ", file_create_err)
        return
    }
    defer os.close(playlist_file)

    formatted_playlist_name := fmt.tprintf("%s\n", playlist_name)
    _, err = os.write(playlist_file, transmute([]byte)formatted_playlist_name)
    if err != nil {
        fmt.eprintln(#procedure, "Could not write to the playlist file: ", err)
        return
    }

    new_playlist := Playlist{
        title = playlist_name,
        playlist_file_path = file_path
    }

    append(&app_state.playlists, new_playlist)
}

// @todo: testing
add_track_to_playlist :: proc(playlist: ^Playlist, track: ^Track, root_dir: string) {
    playlist_file, err := os.open(playlist.playlist_file_path, {.Append, .Write})
    if err != nil {
        fmt.eprintln(#procedure, "Could not open the playlist file: ", err)
        return
    }
    defer os.close(playlist_file)

    relative_track_file_path := fmt.tprintf("%s\n", string(track.file_path)[len(root_dir):])
    _, err = os.write(playlist_file, transmute([]byte)relative_track_file_path)
    if err != nil {
        fmt.eprintln(#procedure, "Failed to write to playlist file", err)
        return
    }

    append(&playlist.tracks, track)
}

delete_playlist :: proc(app_state: ^App_State, playlist: Playlist) {
    // @todo
}


remove_track_from_playlist :: proc(playlist: ^Playlist, track_to_remove: Track) {
    // @todo
}

@require_results
get_or_create_playlist_dir :: proc(path: string) -> os.Error {
    // @todo: should be able to use os.exists
    file_info, file_info_err := os.stat(path, context.allocator)
    if file_info_err != nil || file_info.type != .Directory {
        err := os.mkdir(path)
        if err != nil {
            os.file_info_delete(file_info, context.allocator)
            return err
        }
    }

    os.file_info_delete(file_info, context.allocator)
    return nil
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

handle_create_playlist_modal_keyboard_events :: proc(app_state: ^App_State) {
    assert(app_state.active_viewport == .Create_Playlist_Modal)

    input := rl.GetCharPressed()
    if input > 0 {
        append(&app_state.create_playlist_modal_input, input)
    }

    if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
        clear(&app_state.create_playlist_modal_input)

        app_state.is_create_playlist_modal_open = false
        app_state.active_viewport = .Main

    }

    if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
        // @todo: create the playlist
        // do not allow empty input or duplicate playlist names

        /*clear(&app_state.create_playlist_modal_input)
        app_state.is_create_playlist_modal_open = false
        app_state.active_viewport = .Main*/
    }

}
