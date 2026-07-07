package main

// playlist will be file based
// dir under library dir "$LIBRARY_PATH/.mppl/mppl0; .mppl/mppl1 etc"  
// Format:
// First line is playlist name
// next lines are paths to tracks (relative or absolute path?)

// Playlist will be a track list without grouping
// each playlist is it's own separate view. Like artist view

Playlist :: struct {
    title: string,
    tracks_file_paths: [dynamic]cstring, // @note: use these to find tracks in app_state.tracks list
    tracks: [dynamic]^Track
}

get_playlists :: proc() -> [dynamic]Playlist {
    return {}
}

create_playlist :: proc() {
}

delete_playlist :: proc() {
}

add_track_to_playlist :: proc() {
}

remove_track_from_playlist :: proc() {
}


