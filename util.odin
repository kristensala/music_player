package main

import "core:sort"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import "core:fmt"
import "core:os"
import tl "taglib"
import ma "vendor:miniaudio"
import rl "vendor:raylib"

// @todo
// ~/.config/music_player/config
// create ~/.config/music_player/playlists/mppl1
// mppl2 (music player playlist 2)
// each row is path to the track and the first row is the name of the playlist
@private
load_config :: proc() {
    home_dir, err  := os.user_home_dir(context.allocator)
    config_path, join_err := filepath.join({home_dir, ".config", "music_player"}, context.allocator)

    //os.exists
    config_files, read_path_err := os.read_directory_by_path(config_path, 1, context.allocator)
    if read_path_err == .Not_Exist {
        if make_dir_err := os.make_directory_all(config_path); err != nil {
            fmt.eprintln("Could not create config dir")
            return
        }

    }
    defer delete(config_files)

    config_file_path, e := filepath.join({config_path, "config"}, context.allocator)
    config_file, open_config_file_err := os.open(config_file_path, flags = {.Read, .Create}, perm = {.Read_User, .Write_User})

    if open_config_file_err != nil {
        fmt.eprintln("Could not read config file")
        return
    }
    defer os.close(config_file)
}

@private
handle_keyboard_events :: proc(app_state: ^App_State) {
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
        if app_state.ma_sound == nil {
            return
        }

        handle_play_pause(app_state)
    }
}

@private
walk_music_dir :: proc(app_state: ^App_State, path: string) {
    data, err := os.read_directory_by_path(path, 0, context.allocator)
    if err != nil {
        fmt.printf("Could not read the dir", err)
        return
    }
    defer delete(data)

    album_map := make(map[cstring]int)
    defer delete(album_map)

    current_album: ^Album

    for d in data {
        if d.type == .Directory {
            walk_music_dir(app_state, d.fullpath)
        } else if d.type == .Regular {
            if filepath.ext(d.fullpath) == ".mp3" || filepath.ext(d.fullpath) == ".flac" || filepath.ext(d.fullpath) == ".wav" {
                // @todo: if image found `cover.jpeg/png` save to a map with base path as key
                // map[string]string and value as path to the cover art
                // after the tracks are found, use track file_path and match with the cover art path

                //fmt.printfln(d.fullpath)
                tag, tl_error := tl.get_tag(d.fullpath)
                //fmt.printfln("md.title len=%d value=%q", len(tag.title), tag.title)

                track := Track{
                    title = strings.clone_to_cstring(tag.title),
                    artist = strings.clone_to_cstring(tag.artist),
                    album = strings.clone_to_cstring(tag.album),
                    file_name = strings.clone_to_cstring(d.name),
                    file_path = strings.clone_to_cstring(d.fullpath)
                }

                // create album
                {
                    idx, album_exists := album_map[track.album]
                    if !album_exists {
                        idx = len(app_state.albums)

                        album := Album{
                            title = track.album,
                            artist = track.artist,
                            cover_art_cache_entry_idx = -1
                        }
                        append(&app_state.albums, album)
                        album_map[track.album] = idx
                    }
                    track.album_idx = i32(idx)

                    track_idx := len(app_state.tracks)
                    append(&app_state.albums[idx].track_indices, i32(track_idx))

                    track_pos := len(app_state.albums[idx].track_indices) - 1
                    track.order_nr_in_album = i32(track_pos)

                    current_album = &app_state.albums[len(app_state.albums) - 1]
                }

                append(&app_state.tracks, track)
                tl.tag_destroy(&tag)

                if !slice.contains(app_state.artist_list[:], current_album.artist) {
                    append(&app_state.artist_list, current_album.artist)
                }

            } else if filepath.ext(d.fullpath) == ".jpg" || filepath.ext(d.fullpath) == ".jpeg" || filepath.ext(d.fullpath) == ".png" {
                // found an image. Assume this is the cover for the album
                if current_album != nil {
                    current_album.cover_art_path = strings.clone_to_cstring(d.fullpath)
                }
            }
        }
    }

    // @todo: ignore case
    sort.quick_sort(app_state.artist_list[1:])
}

@private
handle_next_song_pick :: proc(app_state: ^App_State) {
    current_album := app_state.albums[app_state.currently_playing.album_idx]
    next_track : ^Track = nil

    assert(app_state.currently_playing != nil)

    // Is last song of the album. Switch to the next one
    if len(current_album.track_indices) - 1 == int(app_state.currently_playing.order_nr_in_album) {
        is_last_album := len(app_state.albums) - 1  == int(app_state.currently_playing.album_idx)
        if is_last_album {
            app_state.currently_playing = nil
            app_state.ma_sound = nil
            app_state.audio_state = .Stopped
            return
        }

        next_track_idx := app_state.albums[app_state.currently_playing.album_idx + 1].track_indices[0]
        next_track = &app_state.tracks[next_track_idx]
    } else {
        next_track_idx := current_album.track_indices[app_state.currently_playing.order_nr_in_album + 1]
        next_track = &app_state.tracks[next_track_idx]
    }

    ma.sound_uninit(app_state.ma_sound)
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.currently_playing = nil

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
                app_state.currently_playing = next_track
            }
        }
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

@private
build_rows :: proc(app_state: ^App_State) {
    rows : [dynamic]^Row
    pos_y : i32 = i32(app_state.main_panel.y)

    for &album, album_idx in app_state.albums {
        if app_state.selected_artist != nil {
            if album.artist != app_state.selected_artist do continue
        }

        album_title_row := new(Row)
        album_title_row.is_album_row = true
        album_title_row.album_idx = i32(album_idx)

        append(&rows, album_title_row)

        pos_y = pos_y + ROW_HEIGHT

        album_content_height : i32 = 0
        for track_idx in album.track_indices {
            track := &app_state.tracks[track_idx]
            assert(track != nil)

            track_row := new(Row)
            track_row.track = track

            append(&rows, track_row)

            pos_y = pos_y + ROW_HEIGHT
            album_content_height += ROW_HEIGHT
        }

        if album_content_height < 200 {
            diff := (200 - album_content_height) / ROW_HEIGHT
            for i in 0..<diff{
                append(&rows, nil)
            }
        }

        pos_y = pos_y + ROW_HEIGHT // padding after the album
    }

    app_state.rows = rows
    app_state.content_max_height = pos_y
}

@private
least_used_cover_art_idx :: proc(app_state: ^App_State) -> (cache_entry_idx: i32, cache_entry: ^Album_Art_Cache_Entry) {
    smallest_usage : u64
    entry_idx: i32
    e : ^Album_Art_Cache_Entry

    for entry, idx in app_state.album_art_cache.entries {
        if idx == 0 {
            smallest_usage = entry.frame
            entry_idx = i32(idx)
            e = entry
            continue
        }

        if entry.frame < smallest_usage {
            smallest_usage = entry.frame
            entry_idx = i32(idx)
            e = entry
        }
    }

    return entry_idx, e
}

@private
request_cover_load :: proc(queue: ^[dynamic]i32, album_idx: i32) {
    if len(queue) == 15 do return

    is_in_queue := false
    for item in queue {
        if item == album_idx {
            is_in_queue = true
            return
        }
    }
    if is_in_queue do return
    append(queue, album_idx)
}

@private
process_album_art_queue :: proc(app_state: ^App_State) {
    for album_idx, idx in app_state.album_art_load_queue {
        album := &app_state.albums[album_idx]

        fmt.println("loading album art for: ", album.title)

        if len(album.cover_art_path) > 0 {
            // cache is full
            if app_state.album_art_cache.count >= 15 {
                cache_entry_idx, cache_entry := least_used_cover_art_idx(app_state)
                least_used_album := &app_state.albums[cache_entry.album_idx]
                least_used_album.cover_art_cache_entry_idx = -1
                current_entry := app_state.album_art_cache.entries[cache_entry_idx]
                rl.UnloadTexture(current_entry.texture)

                app_state.album_art_cache.entries[cache_entry_idx] = {}
                app_state.album_art_cache.count -= 1

                img := rl.LoadImage(album.cover_art_path)
                rl.ImageResize(&img, 200, 200)
                texture := rl.LoadTextureFromImage(img)
                rl.UnloadImage(img)

                new_cache_entry := new(Album_Art_Cache_Entry)
                new_cache_entry.album_idx = album_idx
                new_cache_entry.texture = texture
                new_cache_entry.frame = app_state.current_frame_rendered

                app_state.album_art_cache.entries[cache_entry_idx] = new_cache_entry
                album.cover_art_cache_entry_idx = cache_entry_idx
                app_state.album_art_cache.count += 1
            } else {
                img := rl.LoadImage(album.cover_art_path)
                rl.ImageResize(&img, 200, 200)
                texture := rl.LoadTextureFromImage(img)
                rl.UnloadImage(img)

                idx := -1
                for e, i in app_state.album_art_cache.entries {
                    // look for the first empty entry
                    if e == nil {
                        idx = i
                    }
                }
                if idx >= 0 {
                    new_cache_entry := new(Album_Art_Cache_Entry)
                    new_cache_entry.album_idx = album_idx
                    new_cache_entry.texture = texture
                    new_cache_entry.frame = app_state.current_frame_rendered

                    app_state.album_art_cache.entries[idx] = new_cache_entry
                    app_state.album_art_cache.count += 1
                    album.cover_art_cache_entry_idx = i32(idx)
                }
            }
        }
    }

    clear(&app_state.album_art_load_queue)
}

// @todo: buggy
@private
invalidate_cache :: proc(app_state: ^App_State) {
    max_frame_diff : u64 = 1000

    entries_to_remove: [dynamic]i32
    defer delete(entries_to_remove)

    for entry, idx in app_state.album_art_cache.entries {
        if entry == nil do continue

        // entry has not been accessed for the last 1000 frames
        // remove from cache
        if app_state.current_frame_rendered - entry.frame > max_frame_diff {
            append(&entries_to_remove, i32(idx))
        }
    }

    for entry_idx_to_remove in entries_to_remove {
        cache_entry := app_state.album_art_cache.entries[entry_idx_to_remove]
        if cache_entry == nil do continue

        album := &app_state.albums[cache_entry.album_idx]
        if album == nil do continue

        remove_entry_from_cache(&app_state.album_art_cache, entry_idx_to_remove)
        album.cover_art_cache_entry_idx = -1
    }

    fmt.println("---start---")
    for foo in app_state.album_art_cache.entries {
        if foo != nil {
            fmt.printfln("album Idx: %i; entry_frame: %i; current frame: %i", foo.album_idx, foo.frame, app_state.current_frame_rendered)
        }
    }
    fmt.println("\n---end---")
}

@(private = "file")
remove_entry_from_cache :: proc(cache: ^Album_Art_Cache, entry_idx: i32) {
    entry := cache.entries[entry_idx]
    if entry == nil do return

    rl.UnloadTexture(entry.texture)
    cache.entries[entry_idx] = nil
    cache.count -= 1

    assert(cache.count >= 0)
}
