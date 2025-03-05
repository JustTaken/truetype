package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

main :: proc() {
    if len(os.args) != 3 {
        fmt.println("usage:", os.args[0], "{path_to_font}", "{chars}", "\n.eg \"", os.args[0], "assets/font.ttf ABCDEFabcdef123456 \"")
        return
    }

    bytes, allocation_err := mem.alloc_bytes(1024 * 1024 * 30);
    if allocation_err != nil {
        fmt.println("Failed to allocate initial bytes")
        return
    }

    defer mem.free_bytes(bytes)

    arena: mem.Arena
    font: Font
    err: Font_Error

    mem.arena_init(&arena, bytes)

    context.allocator = mem.arena_allocator(&arena)

    font_path := os.args[1]
    chars := os.args[2]

    if font, err = font_from_file(font_path, context.allocator); err != nil {
        fmt.println("failed to read font file with:", err)
        return
    }

    // temp_arena := mem.begin_arena_temp_memory(&arena)
    // null_char_bitmap: Contours_Bitmap

    // if null_char_bitmap, err = font_render_glyph(&font, 0, context.allocator); err != nil {
    //     fmt.println("failed to read null char glyph with", err)
    //     return
    // }

    // write_bitmap_to_file(null_char_bitmap, "assets/images/null.ppm")

    // mem.end_arena_temp_memory(temp_arena)

    for c in chars {
        temp_arena := mem.begin_arena_temp_memory(&arena)

        write_char_to_file(&font, u16(c), context.allocator)

        mem.end_arena_temp_memory(temp_arena)
    }
}

write_char_to_file :: proc(font: ^Font, char: u16, allocator := context.allocator) {
    start_time := time.now()

    allocation_err: mem.Allocator_Error
    bitmap: Contours_Bitmap
    font_err: Font_Error

    if bitmap, font_err = font_render_glyph(font, char, allocator); font_err != nil {
        fmt.println("failed to read glyph --", rune(char), "-- with", font_err)
        return
    }

    bitmap_time := time.now()

    out_buffer: []u8
    out_buffer, allocation_err = make([]u8, 50, allocator)

    if allocation_err != nil {
        fmt.println("Failed to allocate file bytes")
        return
    }

    out_path := fmt.bprintf(out_buffer, "assets/images/{:c}.ppm", rune(char))

    write_bitmap_to_file(bitmap, out_path)

    total_time := time.now()
    fmt.println("glyph", rune(char), "took", bitmap_time._nsec - start_time._nsec, "ns", "total took", total_time._nsec - start_time._nsec, "ns")
}

write_bitmap_to_file :: proc(bitmap: Contours_Bitmap, path: string, allocator := context.allocator) {
    allocation_err: mem.Allocator_Error

    width := u32(bitmap.width)
    height := u32(bitmap.height)
    buf: []u8
    buf, allocation_err = make([]u8, len(bitmap.buffer) * (3 * 3 + 3) + 100, allocator)

    if allocation_err != nil {
        fmt.println("Failed to allocate file bytes")
        return
    }

    header := fmt.bprintf(buf, "P3\n{:d} {:d}\n255\n", width, height)

    count := len(header)

    for y in 0..<height {
        for x in 0..<width {
            b := bitmap.buffer[(height - y - 1) * width + x]
            color := fmt.bprintf(buf[count:], "{:d} {:d} {:d}\n", b, b, b)
            count += len(color)
        }
    }

    if write_err := os.write_entire_file_or_err(path, buf[0:count]); write_err != nil {
        fmt.println("Failed to write to file", write_err)
    }
}
