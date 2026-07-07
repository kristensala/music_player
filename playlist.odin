package main

import "core:os"
import "core:fmt"

// playlist will be file based
// dir under library dir "$LIBRARY_PATH/.mppl/mppl0; .mppl/mppl1 etc"  
// Format:
// First line is playlist name
// next lines are paths to tracks (relative or absolute path?)

// Playlist will be a track list without grouping
// each playlist is it's own separate view. Like artist view

Playlist :: struct {
    title: string,
    playlist_file_path, string,
    tracks_file_paths: [dynamic]cstring, // @note: use these to find tracks in app_state.tracks list
    tracks: [dynamic]^Track
}

@require_results
get_playlists :: proc() -> [dynamic]Playlist {
    return {}
}

create_playlist :: proc(app_state: ^App_State, playlist_name: string) {
    exists, err := playlist_dir_exists(app_state.playlist_path)
    if err != nil || !exists {
        fmt.eprintln("Could not create or read playlist path: ", err)
        return
    }

    // file names mppl0, mppl1, mppl2 etc
}

delete_playlist :: proc(app_state: ^App_State, playlist: Playlist) {
}

add_track_to_playlist :: proc(playlist: ^Playlist, track: ^Track) {
}

remove_track_from_playlist :: proc(playlist: ^Playlist, track_to_remove: Track) {
}

@require_results
playlist_dir_exists :: proc(path: string) -> (bool, os.Error) {
    file_info, file_info_err := os.stat(path, context.allocator)
    if file_info_err != nil {
        err := os.mkdir(path)
        if err != nil {
            return false, err
        }
        return true, nil
    } else if file_info.type == .Directory {
        return true, nil
    }

    return false, nil
}


