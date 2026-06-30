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

SCROLL_INCREMENT  :: 5 // five rows
ALBUM_COVER_SCALE :: 2

ROW_HEIGHT        :: 40

Row :: struct {
    is_album_title_row : bool,
    album_title        : cstring,
    track              : ^Track,
}

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
            if filepath.ext(d.fullpath) == ".mp3" || filepath.ext(d.fullpath) == ".flac" {
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
                /*track := new(Track)
                track.title = strings.clone_to_cstring(tag.title)
                track.artist = strings.clone_to_cstring(tag.artist)
                track.album = strings.clone_to_cstring(tag.album)
                track.file_name = strings.clone_to_cstring(d.name)
                track.file_path = strings.clone_to_cstring(d.fullpath)*/

                append(&app_state.tracks, track)
                tl.tag_destroy(&tag)

                // create album
                {
                    idx, album_exists := album_map[track.album]
                    if !album_exists {
                        idx = len(app_state.albums)

                        album := Album{
                            title = track.album,
                            artist = track.artist
                        }
                        /*album := new(Album)
                        album.title = track.album
                        album.artist = track.artist*/
                        //album.cover_img_texture = app_state.default_album_cover_texture

                        append(&app_state.albums, album)
                        album_map[track.album] = idx
                    }
                    track.album_idx = i32(idx)
                    track_idx := len(app_state.tracks) - 1
                    append(&app_state.albums[idx].track_indices, i32(track_idx))

                    track_pos := len(app_state.albums[idx].track_indices) - 1
                    track.order_nr_in_album = i32(track_pos)

                    current_album = &app_state.albums[len(app_state.albums) - 1]
                }

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

    sort.quick_sort(app_state.artist_list[:])
}

// @todo: could use app_state.rows now
@private
handle_next_song_pick :: proc(app_state: ^App_State) {
    assert(ma.sound_at_end(app_state.ma_sound) == true)

    ma.sound_uninit(app_state.ma_sound)
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped

    current_album := app_state.albums[app_state.currently_playing.album_idx]
    next_track : ^Track = nil

    assert(app_state.currently_playing != nil)

    // @testing
    // @todo: handle if last album
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
get_track_cover_art :: proc(app_state: ^App_State, track: ^Track) -> ^cstring {
    return &app_state.albums[track.album_idx].cover_art_path
}

// @todo:
// if selected_artist != nil then rebuild rows from app_state.artists
@private
build_rows :: proc(app_state: ^App_State) {
    // reset scroll index
    app_state.current_scroll_idx = 0
    pos_y : i32 = i32(app_state.main_panel.y)

    for album in app_state.albums {
        if app_state.selected_artist != nil {
            if album.artist != app_state.selected_artist {
                continue
            }
        }

        album_title_row := Row{
            is_album_title_row = true,
            album_title = album.title
        }
        append(&app_state.rows, album_title_row)

        pos_y = pos_y + ROW_HEIGHT

        // @todo: next should be cover art row

        for track_idx in album.track_indices {
            track := &app_state.tracks[track_idx]
            assert(track != nil)

            track_row := Row{
                track = track
            }
            append(&app_state.rows, track_row)

            pos_y = pos_y + ROW_HEIGHT
        }

        pos_y = pos_y + ROW_HEIGHT // padding after the album
    }
}
