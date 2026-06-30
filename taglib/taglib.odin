package taglib

import "core:unicode/utf16"
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

@private
parse_mp3 :: proc(filepath: string) -> (_tag: Tag, error: Taglib_Error) {
    file, err := os.open(filepath)
    if err != nil {
        fmt.eprintln("Could not open file: ", err)
        return {}, .Failed_To_Read_File
    }
    defer os.close(file)

    header := make([]byte, 10)
    defer delete(header)

    _, read_err := os.read(file, header)
    if read_err != nil {
        fmt.eprintln("Could not read file header: ", err)
        return {}, .Failed_To_Read_File
    }

    file_identifier := header[:3]
    if string(file_identifier) != "ID3" {
        fmt.println("Could not find ID3 tag")
        return {}, nil
    }

    major_version := header[3]
    revision_number := header[4]

    // flags: if byte is 0 then no flags
    // else conver to 8bit binary
    // need an example
    flags := header[5]

    tag := header[6:10]
    assert(len(tag) == 4, "Tag length has to be 4")

    tag_size := synchsafe_to_u32(tag)

    tag_data := make([]byte, tag_size)
    defer delete(tag_data)

    _, read_err = os.read(file, tag_data)
    if read_err != nil {
        fmt.eprintln("Could not read tag_data: ", read_err)
        return {}, nil
    }

    md := mp3_parse_tag(tag_data[:tag_size], tag_size, major_version)
    return md, nil
}

@private
parse_flac :: proc(filepath: string) -> (_tag: Tag, error: Taglib_Error) {
    file, err := os.open(filepath)
    if err != nil {
        fmt.eprintln("Could not open file: ", err)
        return {}, nil
    }
    defer os.close(file)

    header := make([]byte, 4)
    defer delete(header)

    _, read_err := os.read(file, header)
    if read_err != nil {
        fmt.eprintln("Could not read header data from file: ", err)
        return {}, nil
    }

    if string(header[:4]) != "fLaC" {
        fmt.println("invalid signature")
        return {}, nil
    }

    for ;; {
        header := make([]byte, 4)
        defer delete(header)

        _, read_err := os.read(file, header)
        if read_err != nil {
            fmt.eprintln("Could not read header: ", err)
            return
        }

        is_last := (header[0] & 0x80) != 0
        block_type := header[0] & 0x7F
        block_length := read_u32_be(header)

        // found vorbis
        if block_type == 4 {
            block_data := make([]byte, block_length)
            defer delete(block_data)

            _, read_err = os.read(file, block_data)
            if read_err != nil {
                fmt.eprintln("Error")
                return
            }

            return flac_parse_vorbis_comment(block_data), nil
        } else {
            os.seek(file, i64(block_length), .Current)
        }

        if is_last {
            break
        }
    }


    return {}, nil
}

// Vendor data is always first in Vorbis comment block
// Then comes comment count: ARTIST, ALBUM, TITLE etc
@private
flac_parse_vorbis_comment :: proc(vorbis_data: []u8) -> Tag {
    pos := 0
    vendor_length := int(read_u32_le(vorbis_data, pos))
    pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

    vendor := string(vorbis_data[pos:pos + vendor_length])

    pos += vendor_length
    comment_count := int(read_u32_le(vorbis_data, pos))
    pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

    tag := Tag{}

    for i in 0..<comment_count {
        comment_length := int(read_u32_le(vorbis_data, pos))
        pos += FLAC_METADATA_BLOCK_HEADER_LENGTH

        comment := string(vorbis_data[pos:pos + comment_length])
        pos += comment_length

        if strings.has_prefix(comment, "TITLE=") {
            tag.title = strings.clone(comment[len("TITLE="):])
        } else if strings.has_prefix(comment, "ARTIST=") {
            tag.artist = strings.clone(comment[len("ARTIST="):])
        } else if strings.has_prefix(comment, "ALBUM=") {
            tag.album = strings.clone(comment[len("ALBUM="):])
        }
    }

    return tag
}

@private
parse_wav :: proc(file_path: string) {
    // @todo
}

@private
@require_results
mp3_parse_tag :: proc(tag_data: []byte, tag_size: u32, major_version: u8) -> Tag {
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

        frame_size : u32 = 0
        if major_version == 4 {
            frame_size = synchsafe_to_u32(frame_size_bytes)
        } else {
            frame_size = read_u32_be(frame_size_bytes)
        }
        frame := string(tag_data[i:i+frame_length])

        frame_data_start := i + MP3_PADDING
        frame_data_end := i + MP3_PADDING + int(frame_size)
        if frame_data_end > len(tag_data) {
            break
        }

        frame_data := tag_data[frame_data_start:frame_data_end]

        switch frame {
        case "TIT2": 
            result.title = decode_text(frame_data)
        case "TALB":
            result.album = decode_text(frame_data)
        case "TPE1": 
            result.artist = decode_text(frame_data)
        }

        i = i + MP3_PADDING + int(frame_size)
    }

    return result
}

/*
   Frames that allow different types of text encoding contains a text
   encoding description byte. Possible encodings:

     $00   ISO-8859-1 [ISO-8859-1]. Terminated with $00.
     $01   UTF-16 [UTF-16] encoded Unicode [UNICODE] with BOM. All
           strings in the same frame SHALL have the same byteorder.
           Terminated with $00 00.
     $02   UTF-16BE [UTF-16] encoded Unicode [UNICODE] without BOM.
           Terminated with $00 00.
     $03   UTF-8 [UTF-8] encoded Unicode [UNICODE]. Terminated with $00.
 */
@private
decode_text :: proc(data: []byte) -> string {
    if len(data) == 0 {
        return ""
    }
    endcoding := data[0]
    text := data[1:]

    switch endcoding {
    case 0:
        return strings.clone(string(text))
    case 1:
        if len(text) >= 2 && text[0] == 0xff && text[1] == 0xfe {
            return utf16le_to_utf8(text[2:])
        }
        if len(text) >= 2 && text[0] == 0xfe && text[1] == 0xff {
            return utf16be_to_utf8(text[2:])
        }
    }
    return strings.clone(string(text))
}

@private
utf16be_to_utf8 :: proc(data: []u8) -> string {
    src := make([]u16, len(data)/2)
    defer delete(src)

    for i := 0; i < len(src); i += 1 {
        b := i * 2
        src[i] = u16(data[b]) << 8 | u16(data[b + 1])
    }

    dst := make([]u8, len(src)*4)
    defer delete(dst)

    n := utf16.decode_to_utf8(dst, src)
    return strings.clone(string(dst[:n]))
}

@private
utf16le_to_utf8 :: proc(data: []byte) -> string {
    src := make([]u16, len(data)/2)
    defer delete(src)

    for i in 0..<len(src) {
        src[i] = u16(data[2*i]) | u16(data[2*i+1])<<8
    }

    dst := make([]u8, len(src)*4)
    defer delete(dst)

    n := utf16.decode_to_utf8(dst, src)
    return strings.clone(string(dst[:n]))
}

tag_destroy :: proc(tag: ^Tag) {
    delete(tag.title)
    delete(tag.album)
    delete(tag.artist)

    tag.title = ""
    tag.album = ""
    tag.artist = ""
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

