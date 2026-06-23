package main

import "core:strings"
import "core:path/filepath"
import "core:fmt"
import rl "vendor:raylib"
import "core:os"
import ma "vendor:miniaudio"

import tl "taglib"

GUI_PADDING :: 50

App_State :: struct {
    font: map[i32]rl.Font,
    music_dir: string,

    tracks: [dynamic]^Track,
    albums: [dynamic]^Album,
    playlists: [dynamic]Playlist,

    default_album_cover_texture: rl.Texture2D,

    ma_engine: ma.engine,
    ma_sound: ^ma.sound,

    audio_state: AudioState,
    currently_playing: ^Track,

    main_panel: rl.Rectangle,
    main_panel_scroll_offset: i32,
    main_panel_content: Content,
}

Content :: enum {
    Track_List,
    Albums,
    Playlists
}

AudioState :: enum {
    Stopped,
    Playing,
    Paused
}

// custom files
// Use DeaDBeef as an example
Playlist :: struct {
    title: string,
    tracks: [dynamic]Track
}

Track :: struct {
    title: cstring,
    artist: cstring,
    album: cstring,
    album_idx: i32,
    file_path: cstring,
    file_name: cstring,

    order_nr_in_album: i32
}

Album :: struct {
    title: cstring,
    artist: cstring,
    cover_img_texture: rl.Texture2D,
    track_indices: [dynamic]i32 // reference to the app_state.tracks
}

@private
destroy_state :: proc(app_state: ^App_State) {
    ma.sound_uninit(app_state.ma_sound)

    for a in app_state.albums {
        delete(a.track_indices)
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

    free(app_state)
}

main :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE})

    rl.InitWindow(1000, 800, "music_player")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    font_20 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", 20, nil, 0)
    defer rl.UnloadFont(font_20)

    font_30 := rl.LoadFontEx("res/IBMPlexMono-Regular.ttf", 30, nil, 0)
    defer rl.UnloadFont(font_30)

    fonts := make(map[i32]rl.Font)
    defer delete(fonts)

    fonts[20] = font_20
    fonts[30] = font_30

    app_state := new(App_State)
    //app_state.music_dir = "/home/salakris/Music/Michael_Jackson/History Past, Present And Future, Book 1/"
    app_state.music_dir = "/home/salakris/Music/Skinny_Living/"
    app_state.font = fonts
    app_state.ma_sound = nil
    app_state.audio_state = .Stopped
    app_state.main_panel = rl.Rectangle{
        x = 20,
        y = 20
    }
    app_state.main_panel_scroll_offset = 20
    app_state.default_album_cover_texture = rl.LoadTexture("./res/album_placeholder.png")

    walk_music_dir(app_state, app_state.music_dir)
    app_state.albums = create_albums(app_state)

    fmt.println(len(app_state.albums))

    engine_init_result := ma.engine_init(nil, &app_state.ma_engine)
    if engine_init_result != .SUCCESS {
        fmt.println("Could not init Mini audio engine: ", engine_init_result)
        ma.engine_uninit(&app_state.ma_engine)
        return
    }
    defer ma.engine_uninit(&app_state.ma_engine)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)

        app_state.main_panel.width = f32(rl.GetScreenWidth() - 40)
        app_state.main_panel.height = f32(rl.GetScreenHeight() - 150)

        update(app_state)
        draw(app_state)

        rl.EndDrawing()
    }

    // cleanup
    {
        destroy_state(app_state)
    }
}

update :: proc(app_state: ^App_State) {
    if ma.sound_at_end(app_state.ma_sound) {
        handle_next_song_pick(app_state)
    }
}


@private
draw :: proc(app_state: ^App_State) {
    draw_and_handle_album_list(app_state)

    // Bottom bar
    {
        // Display currently playing track
        {
            currently_playing : cstring = ""
            if app_state.currently_playing != nil {
                currently_playing = app_state.currently_playing.file_name
            }
            rl.DrawTextEx(app_state.font[20], currently_playing, {GUI_PADDING, f32(rl.GetScreenHeight() - GUI_PADDING - 25)}, 20, 0, rl.BLACK)
        }

        // Playback conrols
        {
            button_txt : cstring = "play"
            if app_state.audio_state == .Playing {
                button_txt = "pause"
            } else if app_state.audio_state == .Paused || app_state.audio_state == .Stopped {
                button_txt = "play"
            }

            play_button_pressed := button(app_state.font[20],button_txt, {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() - 120)})
            if play_button_pressed {
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
                {GUI_PADDING, f32(rl.GetScreenHeight() - GUI_PADDING)},
                f32(rl.GetScreenWidth() - 100),
                10)
        }
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

    for d in data {
        if d.type == .Directory {
            walk_music_dir(app_state, d.fullpath)
        } else if d.type == .Regular {
            if filepath.ext(d.fullpath) != ".mp3" && filepath.ext(d.fullpath) != ".flac" {
                continue
            }

            // @todo: if image found `cover.jpeg/png` save to a map with base path as key
            // map[string]string and value as path to the cover art
            // after the tracks are found, use track file_path and match with the cover art path

            //fmt.printfln(d.fullpath)
            tag, tl_error := tl.get_tag(d.fullpath)
            //fmt.printfln("md.title len=%d value=%q", len(tag.title), tag.title)

            track := new(Track)
            track.title = strings.clone_to_cstring(tag.title)
            track.artist = strings.clone_to_cstring(tag.artist)
            track.album = strings.clone_to_cstring(tag.album)
            track.file_name = strings.clone_to_cstring(d.name)
            track.file_path = strings.clone_to_cstring(d.fullpath)

            append(&app_state.tracks, track)

            tl.tag_destroy(&tag)
        }
    }
}

@private
create_albums :: proc(app_state: ^App_State) -> [dynamic]^Album {
    album_map := make(map[cstring]int)
    defer delete(album_map)

    albums : [dynamic]^Album

    for track, i in app_state.tracks {
        idx, exists := album_map[track.album]
        if !exists {
            idx = len(albums)

            album := new(Album)
            album.title = track.album
            album.artist = track.artist
            album.cover_img_texture = app_state.default_album_cover_texture

            append(&albums, album)
            album_map[track.album] = idx
        }
        track.album_idx = i32(idx)
        append(&albums[idx].track_indices, i32(i))

        track_pos := len(albums[idx].track_indices) - 1
        track.order_nr_in_album = i32(track_pos)
    }
    return albums
}

@private
draw_and_handle_album_list :: proc(app_state: ^App_State) {
    pressed, selected_track := draw_tracks_list(app_state)
    if pressed {
        fmt.println("selected_track: ", selected_track.order_nr_in_album)
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
                app_state.currently_playing = selected_track
            }
        }
    }
}

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
        next_track = app_state.tracks[next_track_idx]
    } else {
        next_track_idx := current_album.track_indices[app_state.currently_playing.order_nr_in_album + 1]
        next_track = app_state.tracks[next_track_idx]
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

