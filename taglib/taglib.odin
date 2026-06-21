package taglib

import "core:strings"
import "core:fmt"
import "core:os"
import "core:path/filepath"

// MP3
@private MP3_PADDING :: 10

// Flac
@private FLAC_STREAMING_INFO_BLOCK_LENGTH :: 34
@private FLAC_STREAMING_INFO_START_BYTE :: 8
@private FLAC_METADATA_BLOCK_HEADER_LENGTH :: 4

// @todo: custom and system errors
Taglib_Error :: enum {
    None,
    General,
    Failed_To_Read_File,
    ID3_Tag_Not_Found
}

Tag :: struct {
    title: string,
    artist: string,
    album: string,
}

Tag_Field :: enum {
    Artist,
    Title,
    Album
}

@require_results
get_tag :: proc(file_path: string) -> (tag: Tag, err: Taglib_Error) {
    ext := filepath.ext(file_path)

    switch ext {
    case ".mp3": return parse_mp3(file_path)
    case ".flac": return parse_flac(file_path)
    }

    return {}, nil
}

// @todo
set_tag_fields :: proc(filepath: string, values: map[Tag_Field]string) {

}

@private
set_tag_field :: proc(filepath: string, tag_field: Tag_Field) {
}

// @ref: https://datatracker.ietf.org/doc/rfc9639/
// @ref: https://www.ietf.org/archive/id/draft-ietf-cellar-flac-03.html
@private
@require_results
parse_flac :: proc(file_path: string) -> (metadata: Tag, error: Taglib_Error) {
    flac_data, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        // @todo
    }
    defer delete(flac_data)

    if string(flac_data[:4]) != "fLaC" {
        fmt.println("invalid signature")
        return {}, nil
    }

    // Streaminginfo is always first and its length
    // is always 34. Rest of the blocks are in random order
    // Streaminginfo block type is 0
    metadata_block_header := flac_data[4:7]
    block_type := metadata_block_header[0] & 0x7F
    if block_type != 0 {
        fmt.println("First block has to be Streaminginfo")
        return {}, nil
    }

    pos := FLAC_STREAMING_INFO_START_BYTE + FLAC_STREAMING_INFO_BLOCK_LENGTH
    for ;; {
        if pos > len(flac_data) {
            break;
        }

        header := flac_data[pos]
        block_data_start := pos + FLAC_METADATA_BLOCK_HEADER_LENGTH
        block_length := read_u32_be(flac_data, pos)

        // 4 = Vorbis comment (Metadata Block Type)
        if header & 0x7F == 4 {
            vorbis_data := flac_data[block_data_start:block_data_start+int(block_length)]
            flac_parse_vorbis_comment(vorbis_data)
            // @todo: return tag
            break;
        }

        pos = block_data_start + int(block_length)
    }
    return {}, nil
}

// Vendor data is always first in Vorbis comment block
// Then comes comment count: ARTIST, ALBUM, TITLE etc
// @todo: return tag
@private
flac_parse_vorbis_comment :: proc(vorbis_data: []u8) -> ^Tag {
    pos := 0
    vendor_length := int(read_u32_le(vorbis_data, pos))
    pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

    vendor := string(vorbis_data[pos:pos + vendor_length])

    pos += vendor_length
    comment_count := int(read_u32_le(vorbis_data, pos))
    pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

    for i in 0..<comment_count {
        comment_length := int(read_u32_le(vorbis_data, pos))
        pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

        comment := string(vorbis_data[pos:pos + comment_length])
        pos += comment_length
        fmt.println("Comment: ", comment)
    }

    return nil
}

@private
parse_wav :: proc(file_path: string) {
    // @todo
}

// @specification: https://id3.org/id3v2.4.0-structure
// @todo: Check the PADDING. Seems random
@private
@require_results
parse_mp3 :: proc(file_path: string) -> (_tag: Tag, error: Taglib_Error) {
    mp3_file_data, err := os.read_entire_file_from_path(file_path, context.allocator)
    if err != nil {
        return {}, .Failed_To_Read_File
    }
    defer delete(mp3_file_data)

    file_identifier := mp3_file_data[:3]
    if string(file_identifier) != "ID3" {
        fmt.println("Could not find ID3 tag")
        return {}, .ID3_Tag_Not_Found
    }

    major_version := mp3_file_data[3]
    revision_number := mp3_file_data[4]

    // flags: if byte is 0 then no flags
    // else conver to 8bit binary
    // need an example
    flags := mp3_file_data[5]

    tag := mp3_file_data[6:10]
    assert(len(tag) == 4, "Tag length has to be 4")

    tag_size := synchsafe_to_u32(tag)

    fmt.println("file: ", file_path)
    md := mp3_parse_tag(mp3_file_data[10:10+tag_size], tag_size)
    return md, nil
}

@private
@require_results
mp3_parse_tag :: proc(tag_data: []byte, tag_size: u32) -> Tag {
    frame_length := 4
    result := Tag{}

    for i := 0; i < int(tag_size); {
        start := i + frame_length
        end := i + (frame_length * 2)
        if start > len(tag_data) || end > len(tag_data) {
            break
        }

        frame_size_bytes := tag_data[start:end]
        assert(len(frame_size_bytes) == 4, "Frame length has to be 4")

        frame_size := read_u32_be(frame_size_bytes)
        frame := string(tag_data[i:i+frame_length])

        frame_data_start := i + MP3_PADDING
        frame_data_end := i + MP3_PADDING + int(frame_size)
        if frame_data_end > len(tag_data) {
            break
        }

        frame_data := tag_data[frame_data_start:frame_data_end]

        fmt.printfln("%s: %s", frame, string(frame_data))

        switch frame {
        case "TIT2": 
            result.title = strings.clone(string(frame_data))
        case "TALB":
            result.album = strings.clone(string(frame_data))
        case "TPE1": 
            result.artist = strings.clone(string(frame_data))
        }

        i = i + MP3_PADDING + int(frame_size)
    }

    return result
}

@private
@(require_results)
synchsafe_to_u32 :: proc(data: []byte) -> u32 {
    return ((u32(data[0]) << 21) | (u32(data[1]) << 14) | (u32(data[2]) << 7) | u32(data[3]))
}

// Little endian
// Vorbis comment field lengths are little-endian coded
@private
@require_results
read_u32_le :: proc(data: []u8, pos: int) -> u32 {
    return u32(data[pos]) | (u32(data[pos + 1]) << 8) | (u32(data[pos + 2]) << 16) | (u32(data[pos + 3]) << 24)
}

// Big Endian
@private
@require_results
read_u32_be :: proc(data: []u8, pos: int = 0) -> u32 {
    return u32(data[pos+1]) << 16 | u32(data[pos+2]) << 8 | u32(data[pos+3])
}

