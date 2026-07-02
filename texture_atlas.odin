package main

import rl "vendor:raylib"

COVER_SIZE :: 200
ATLAS_COLS :: 4
ATLAS_ROWS :: 4
ATLAS_CAPACITY :: ATLAS_COLS * ATLAS_COLS

Album_Cover_Texture_Atlas :: struct {
    image: rl.Image,
    texture: rl.Texture2D,
}

Album_Cover_Sprite :: struct {
    slot: i32,
    lastUsedFrame: i32
}

// @testing
build_texture_atlas :: proc() {
    atlas_img := rl.GenImageColor(
                   ATLAS_COLS * COVER_SIZE,
                   ATLAS_ROWS * COVER_SIZE,
                   rl.RED)
    defer rl.UnloadImage(atlas_img)

    atlas_texture := rl.LoadTextureFromImage(atlas_img)
    defer rl.UnloadTexture(atlas_texture)

    cover_foo := rl.LoadImage("/home/salakris/Music/10_Years/10 Years - Deconstructed/cover.jpg")
    rl.ImageResize(&cover_foo, COVER_SIZE, COVER_SIZE)
    defer rl.UnloadImage(cover_foo)

    cover_bar := rl.LoadImage("/home/salakris/Music/VEELA/Versatile/cover.png")
    rl.ImageResize(&cover_bar, COVER_SIZE, COVER_SIZE)
    defer rl.UnloadImage(cover_bar)

    ok, bar_slot := get_sprite_slot(0)
    if ok {
        rl.ImageDraw(&atlas_img, cover_bar, rl.Rectangle{0, 0, COVER_SIZE, COVER_SIZE}, bar_slot, rl.WHITE)
        rl.UpdateTextureRec(atlas_texture, bar_slot, cover_bar.data)
    }

    valid, foo_slot := get_sprite_slot(15)
    if valid {
        rl.ImageDraw(&atlas_img, cover_foo, rl.Rectangle{0, 0, COVER_SIZE, COVER_SIZE}, foo_slot, rl.WHITE)
        rl.UpdateTextureRec(atlas_texture, foo_slot, cover_foo.data)
    }

    rl.UpdateTexture(atlas_texture, atlas_img.data)

    result := rl.LoadImageFromTexture(atlas_texture)
    rl.UnloadImage(result)

    rl.ExportImage(result, "./res/test.png")

    get_sprite_by_slot(atlas_img, 0)

}

get_sprite_slot :: proc(slot: i32) -> (ok: bool, r: rl.Rectangle) {
    if slot < 0 || slot > ATLAS_CAPACITY - 1 do return false, {}

    x := f32((slot % ATLAS_COLS) * 200)
    y := f32((slot / ATLAS_ROWS) * 200)
    return true, rl.Rectangle{x,y, 200, 200}
}

get_sprite_by_slot :: proc(atlas_img: rl.Image, slot: i32) {
    ok, src := get_sprite_slot(slot)

    if ok {
        img := rl.ImageFromImage(atlas_img, src)
        defer rl.UnloadImage(img)

        rl.ExportImage(img, "./res/cover.png")
    }
}

