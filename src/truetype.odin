package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:math"

Font_Error :: enum u8 {
    None,
    Out_Of_Memory,
    File_Not_Found,
    Number_Read,
    Slice_Read,
    Glyph_Not_Found,
    Glyph_Not_Supported,
    Format_Not_Supported,
    Not_Unicode_Format,
    Version,
    Magic_Number,
    Index_To_Loc,
    Matching_Intersection,
}

F2Dot14 :: u16

Fixed :: struct {
    i: u16,
    f: u16,
}


Font :: struct {
    head_table: Head_Table,
    maxp_table: Maxp_Table,
    hhea_table: Hhea_Table,
    glyf_table: Glyf_Table,
    loca_table: Loca_Table,
    cmap_table: Cmap_Table,
    data: []u8,
}

Table_Tag :: enum(u32) {
    cmap = u32('c') << 24 + u32('m') << 16 + u32('a') << 8 + u32('p'),
    glyf = u32('g') << 24 + u32('l') << 16 + u32('y') << 8 + u32('f'),
    head = u32('h') << 24 + u32('e') << 16 + u32('a') << 8 + u32('d'),
    hhea = u32('h') << 24 + u32('h') << 16 + u32('e') << 8 + u32('a'),
    hmtx = u32('h') << 24 + u32('m') << 16 + u32('t') << 8 + u32('x'),
    loca = u32('l') << 24 + u32('o') << 16 + u32('c') << 8 + u32('a'),
    maxp = u32('m') << 24 + u32('a') << 16 + u32('x') << 8 + u32('p'),
    name = u32('n') << 24 + u32('a') << 16 + u32('m') << 8 + u32('e'),
    post = u32('p') << 24 + u32('o') << 16 + u32('s') << 8 + u32('t'),
}

Table_Directory_Entry :: struct {
    tag: Table_Tag,
    check_sum: u32,
    offset: u32,
    length: u32,
}

Offset_Table :: struct {
    scalar_type: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
}

Cmap_Table :: struct {
    version: u16,
    subtables: []Cmap_Subtable,
}

Cmap_Subtable :: struct {
    id: u16,
    specific_id: u16,
    offset: u32,
    format: Cmap_Format,
}

Cmap_Format :: union {
    Cmap_Format4,
    Cmap_Format12,
}

Cmap_Format4 :: struct {
    format: u16,
    length: u16,
    language: u16,
    seg_count: u16,
    search_range: u16,
    range_shift: u16,
    entry_selector: u16,
    end_code: []u16,
    start_code: []u16,
    id_delta: []u16,
    id_range_offset: []u16,
    glyph_index_array: []u8,
}

Cmap_Format12 :: struct {
    length: u32,
    language: u32,
    groups: []Cmap_Format12_Group,
}

Cmap_Format12_Group :: struct {
    start: u32,
    end: u32,
    glyph: u32,
}

Maxp_Table :: struct {
    version: Fixed,
    glyphs: u16,
    points: u16,
    contours: u16,
    component_points: u16,
    component_contours: u16,
    zones: u16,
    twilight_points: u16,
    storage: u16,
    function_defs: u16,
    stack_elements: u16,
    size_of_instructions: u16,
    component_elements: u16,
    component_depth: u16,
}

Head_Table :: struct {
    version: Fixed,
    font_revision: Fixed,
    check_sum_adjustment: u32,
    magic_number: u32,
    flags: u16,
    units_per_em: u16,
    created: i64,
    modified: i64,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    mac_style: u16,
    lowest_rec_ppe_m: u16,
    font_direction_hint: i16,
    index_to_loc_format: i16,
    glyph_data_format: i16,
}

Hhea_Table :: struct {
    version: Fixed,
    ascent: i16,
    descent: i16,
    line_gap: i16,
    advance_width_max: u16,
    min_left_side_bearing: i16,
    min_right_side_bearing: i16,
    x_max_extent: i16,
    caret_slope_rise:i16,
    caret_slope_run: i16,
    caret_offset: i16,
    metric_data_format: i16,
    num_of_long_hor_metrics: u16,
}

Loca_Table :: struct {
    reader: ByteReader,
    f: proc(^Loca_Table, u16) -> (u32, Font_Error),
}

Glyf_Table :: struct {
    loca: Loca_Table,
    cmap: Cmap_Table,
    bytes: []u8,
}

Glyph_Description :: struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
}

Glyph :: union {
    Simple_Glyph,
    Compound_Glyph,
}

Contours_Bitmap :: struct {
    buffer: []u8,
    width: u32,
    height: u32,
}

Simple_Glyph_Flag :: enum(u8) {
    On_Curve,
    X_Short,
    Y_Short,
    Repeat,
    X_Same,
    Y_Same,
    _,
    _,
}

Simple_Glyph_Flags :: bit_set[Simple_Glyph_Flag]

Simple_Glyph :: struct {
    end_pts_of_contours: []u16,
    instructions: []u8,
    flags: []Simple_Glyph_Flags,
    x_coords: []f32,
    y_coords: []f32,
}

Compound_Glyph_Flag :: enum(u16) {
    Are_Word,
    Are_Values,
    Round_To_Grid,
    Have_Scale,
    _,
    More_Components,
    Have_XY_Scale,
    Have_Two_By_Two,
    Have_Instructions,
    Use_Metrics,
    Overlap,
    _,
    _,
    _,
    _,
    _,
}

Compound_Glyph_Flags :: bit_set[Compound_Glyph_Flag]

Compound_Glyph_Component :: struct {
    flag: Compound_Glyph_Flags,
    index: u16,
    transformation: Glyph_Transformation,
}

Compound_Glyph :: struct {
    components: []Compound_Glyph_Component,
    instructions: []u8,
}

Contour_Orientation :: enum(u8) {
    Clockwise,
    CounterClockwise,
}

Point :: [2]f32

Contour :: struct {
    points: []Point,
    orientation: Contour_Orientation,
}

Contour_Intersection :: struct {
    contour_orientation: Contour_Orientation,
    contour_id: u8,
    x_coord: u32,
}

Glyph_Transformation :: matrix[3, 3]f32
IDENTITY := Glyph_Transformation {
    1, 0, 0,
    0, 1, 0,
    0, 0, 1
}

font_from_file :: proc(file_path: string, allocator := context.allocator) -> (font: Font, err: Font_Error) {
    ok: bool

    font.data, ok = os.read_entire_file(file_path, allocator);

    if !ok {
        return font, .File_Not_Found
    }

    reader := reader_from_bytes(font.data)
    offset_table := read_offset_table(&reader) or_return

    tables: map[Table_Tag]Table_Directory_Entry

    for i in 0..<offset_table.num_tables {
        table_directory_entry := table_directory_entry_from_bytes(&reader) or_return
        tables[table_directory_entry.tag] = table_directory_entry
    }

    font.head_table = read_head_table(tables[.head], font.data) or_return
    font.maxp_table = read_maxp_table(tables[.maxp], font.data) or_return
    font.hhea_table = read_hhea_table(tables[.hhea], font.data) or_return
    font.glyf_table = read_glyf_table(tables[.glyf], font.data)
    font.loca_table = read_loca_table(tables[.loca], font.head_table, font.data) or_return
    font.cmap_table = read_cmap_table(tables[.cmap], font.data, allocator) or_return

    return
}

font_render_glyph :: proc(font: ^Font, char: u16, allocator := context.allocator) -> (bitmap: Contours_Bitmap, err: Font_Error) {
    alloc_err: mem.Allocator_Error
    glyph: Glyph
    contours: []Contour

    index := cmap_get_index(&font.cmap_table, char) or_return
    glyph, bitmap.width, bitmap.height = get_glyph(&font.glyf_table, nil, &font.loca_table, index) or_return

    if contours, alloc_err = get_glyph_contours(&glyph, &font.glyf_table, &font.loca_table); alloc_err != nil {
        return bitmap, .Out_Of_Memory
    }

    if generate_contours_bitmap(&bitmap, contours, 1.0, allocator) != nil {
        return bitmap, .Out_Of_Memory
    }

    return
}

table_tag_from_int :: proc(bytes: []u8) -> Table_Tag {
    sum: u32
    l := len(bytes) - 1

    for b, index in bytes {
        sum += u32(b) << (u32(l - index) * 8)
    }

    return cast(Table_Tag)sum
}

table_directory_entry_from_bytes :: proc(reader: ^ByteReader) -> (table: Table_Directory_Entry, err: Font_Error) {
    table.tag = table_tag_from_int(read_n(reader, 4) or_return)
    table.check_sum = read_u32(reader) or_return
    table.offset = read_u32(reader) or_return
    table.length = read_u32(reader) or_return

    return
}

read_offset_table :: proc(reader: ^ByteReader) -> (table: Offset_Table, err: Font_Error) {
    table.scalar_type = read_u32(reader) or_return
    table.num_tables = read_u16(reader) or_return
    table.search_range = read_u16(reader) or_return
    table.entry_selector = read_u16(reader) or_return
    table.range_shift = read_u16(reader) or_return

    return
}

read_cmap_format4 :: proc(reader: ^ByteReader, allocator := context.allocator) -> (format: Cmap_Format4, err: Font_Error) {
    format.length = read_u16(reader) or_return
    format.language = read_u16(reader) or_return
    format.seg_count = (read_u16(reader) or_return) / 2
    format.search_range = read_u16(reader) or_return
    format.entry_selector = read_u16(reader) or_return
    format.range_shift = read_u16(reader) or_return

    format.end_code = read_n_u16(reader, uint(format.seg_count), allocator) or_return

    _ = read_u16(reader) or_return

    format.start_code = read_n_u16(reader, uint(format.seg_count), allocator) or_return
    format.id_delta = read_n_u16(reader, uint(format.seg_count), allocator) or_return
    format.id_range_offset = read_n_u16(reader, uint(format.seg_count), allocator) or_return

    format.glyph_index_array = reader.buffer[reader.index:]

    return
}

read_cmap_format12 :: proc(reader: ^ByteReader, allocator := context.allocator) -> (format: Cmap_Format12, err: Font_Error) {
    alloc_err: mem.Allocator_Error

    _ = read_u16(reader) or_return
    format.length = read_u32(reader) or_return
    format.language = read_u32(reader) or_return
    group_count := read_u32(reader) or_return

    format.groups, alloc_err = make([]Cmap_Format12_Group, uint(group_count), allocator)

    if alloc_err != nil {
        return format, .Out_Of_Memory
    }

    for i in 0..<group_count {
        format.groups[i].start = read_u32(reader) or_return
        format.groups[i].end = read_u32(reader) or_return
        format.groups[i].glyph = read_u32(reader) or_return
    }

    return
}

read_cmap_format_from_bytes :: proc(bytes: []u8, allocator := context.allocator) -> (format: Cmap_Format, err: Font_Error) {
    reader := reader_from_bytes(bytes)

    Kind :: enum(u16) {
        Format4 = 4,
        Format12 = 12,
    }

    f := Kind(read_u16(&reader) or_return)

    switch f {
        case .Format4: format = read_cmap_format4(&reader, allocator) or_return
        case .Format12: format = read_cmap_format12(&reader, allocator) or_return
        case: err = .Format_Not_Supported
    }

    return
}

cmap_format4_get_index :: proc(format: ^Cmap_Format4, char: u16) -> (u: u16, err: Font_Error) {
    for i in 0..<format.seg_count {
        if !(format.start_code[i] <= char && format.end_code[i] >= char) {
            continue
        }

        switch format.id_range_offset[i] {
            case 0: u = format.id_delta[i] + char
            case: {
                reader := reader_from_bytes(format.glyph_index_array)
                index_offset := i + format.id_range_offset[i] / 2 + (char - format.start_code[i])
                u = read_u16_from_offset(&reader, uint(index_offset - format.seg_count)) or_return
            }
        }

        return
    }

    return 0, .Glyph_Not_Found
}

cmap_format12_get_index :: proc(format: ^Cmap_Format12, char: u16) -> (u16, Font_Error) {
    c := u32(char)

    for group in format.groups {
        if group.start <= c && group.end >= c {
            return u16(group.glyph + (c - group.start)), nil
        }
    }

    return 0, .Glyph_Not_Found
}

cmap_format_get_index :: proc(format: ^Cmap_Format, char: u16) -> (u: u16, err: Font_Error) {
    switch &f in format {
        case Cmap_Format4: u = cmap_format4_get_index(&f, char) or_return
        case Cmap_Format12: u = cmap_format12_get_index(&f, char) or_return
    }

    return
}

is_subtable_unicode :: proc(subtable: Cmap_Subtable) -> bool {
    return subtable.id == 0 || (subtable.id == 3 && subtable.specific_id == 1 || subtable.specific_id == 10)
}

read_cmap_subtable :: proc(reader: ^ByteReader, allocator := context.allocator) -> (subtable: Cmap_Subtable, err: Font_Error) {
    subtable.id = read_u16(reader) or_return
    subtable.specific_id = read_u16(reader) or_return

    subtable.offset = read_u32(reader) or_return
    subtable.format = read_cmap_format_from_bytes(reader.buffer[subtable.offset:], allocator) or_return

    return
}

read_cmap_table :: proc(table: Table_Directory_Entry, bytes: []u8, allocator := context.allocator) -> (cmap: Cmap_Table, err: Font_Error) {
    reader := reader_from_bytes(bytes[table.offset:])

    cmap.version = read_u16(&reader) or_return
    num_subtables := read_u16(&reader) or_return
    cmap.subtables = make([]Cmap_Subtable, num_subtables, allocator)

    if cmap.version != 0 {
        return cmap, .Version
    }

    for i in 0..<num_subtables {
        cmap.subtables[i] = read_cmap_subtable(&reader, allocator) or_continue
    }

    return
}

cmap_get_index :: proc(cmap: ^Cmap_Table, char: u16) -> (u16, Font_Error) {
    for &subtable in cmap.subtables {
        if !is_subtable_unicode(subtable) {
            continue
        }

        u, e := cmap_format_get_index(&subtable.format, char)

        if e == nil {
            return u, nil
        }
    }

    return 0, .Glyph_Not_Found
}

read_maxp_table :: proc(table: Table_Directory_Entry, bytes: []u8) -> (maxp: Maxp_Table, err: Font_Error) {
    reader := reader_from_bytes(bytes[table.offset:])

    maxp.version = read_fixed(&reader) or_return
    maxp.glyphs = read_u16(&reader) or_return
    maxp.points = read_u16(&reader) or_return
    maxp.contours = read_u16(&reader) or_return
    maxp.component_points = read_u16(&reader) or_return
    maxp.component_contours = read_u16(&reader) or_return
    maxp.zones = read_u16(&reader) or_return
    maxp.twilight_points = read_u16(&reader) or_return
    maxp.storage = read_u16(&reader) or_return
    maxp.function_defs = read_u16(&reader) or_return
    maxp.stack_elements = read_u16(&reader) or_return
    maxp.size_of_instructions = read_u16(&reader) or_return
    maxp.component_elements = read_u16(&reader) or_return
    maxp.component_depth = read_u16(&reader) or_return

    if maxp.version.f != 0 || maxp.version.i != 1 {
        return maxp, .Version
    }

    return
}

read_head_table :: proc(table: Table_Directory_Entry, bytes: []u8) -> (head: Head_Table, err: Font_Error) {
    reader := reader_from_bytes(bytes[table.offset:])

    head.version = read_fixed(&reader) or_return
    head.font_revision = read_fixed(&reader) or_return
    head.check_sum_adjustment = read_u32(&reader) or_return
    head.magic_number = read_u32(&reader) or_return
    head.flags = read_u16(&reader) or_return
    head.units_per_em = read_u16(&reader) or_return
    head.created = read_i64(&reader) or_return
    head.modified = read_i64(&reader) or_return
    head.x_min = read_i16(&reader) or_return
    head.y_min = read_i16(&reader) or_return
    head.x_max = read_i16(&reader) or_return
    head.y_max = read_i16(&reader) or_return
    head.mac_style = read_u16(&reader) or_return
    head.lowest_rec_ppe_m = read_u16(&reader) or_return
    head.font_direction_hint = read_i16(&reader) or_return
    head.index_to_loc_format = read_i16(&reader) or_return
    head.glyph_data_format = read_i16(&reader) or_return

    if head.magic_number != 0x5F0F3CF5 {
        return head, .Magic_Number
    }

    if head.version.i != 1 && head.version.f != 0 {
        return head, .Version
    }

    return
}

read_hhea_table :: proc(table: Table_Directory_Entry, bytes: []u8) -> (hhea: Hhea_Table, err: Font_Error) {
    reader := reader_from_bytes(bytes[table.offset:])

    hhea.ascent = read_i16(&reader) or_return
    hhea.descent = read_i16(&reader) or_return
    hhea.line_gap = read_i16(&reader) or_return
    hhea.advance_width_max = read_u16(&reader) or_return
    hhea.min_left_side_bearing = read_i16(&reader) or_return
    hhea.min_right_side_bearing = read_i16(&reader) or_return
    hhea.x_max_extent = read_i16(&reader) or_return
    hhea.caret_slope_rise = read_i16(&reader) or_return
    hhea.caret_slope_run = read_i16(&reader) or_return
    hhea.caret_offset = read_i16(&reader) or_return

    assert((read_i16(&reader) or_return) == 0)
    assert((read_i16(&reader) or_return) == 0)
    assert((read_i16(&reader) or_return) == 0)
    assert((read_i16(&reader) or_return) == 0)

    hhea.metric_data_format = read_i16(&reader) or_return
    hhea.num_of_long_hor_metrics = read_u16(&reader) or_return

    if hhea.version.i != 1 && hhea.version.f != 0 {
        return hhea, .Version
    }

    return
}

loca_table_read_short :: proc(loca: ^Loca_Table, offset: u16) -> (value: u32, err: Font_Error) {
    r := read_u16_from_offset(&loca.reader, uint(offset)) or_return
    value = u32(2 * r)
    return
}

loca_table_read_long :: proc(loca: ^Loca_Table, offset: u16) -> (value: u32, err: Font_Error) {
    value = read_u32_from_offset(&loca.reader, uint(offset)) or_return
    return
}

read_loca_table :: proc(table: Table_Directory_Entry, head: Head_Table, bytes: []u8) -> (loca: Loca_Table, err: Font_Error) {
    loca.reader = reader_from_bytes(bytes[table.offset:])
    IndexToLocFormat :: enum {
        Short = 0,
        Long = 1,
    }

    format := IndexToLocFormat(head.index_to_loc_format)

    switch format {
        case .Short: loca.f = loca_table_read_short
        case .Long: loca.f = loca_table_read_long
        case: return loca, .Index_To_Loc
    }

    return
}

read_glyf_table :: proc(table: Table_Directory_Entry, bytes: []u8) -> Glyf_Table {
    glyf: Glyf_Table = ---
    glyf.bytes = bytes[table.offset:]

    return glyf
}

read_glyph_description :: proc(reader: ^ByteReader) -> (description: Glyph_Description, err: Font_Error) {
    description.number_of_contours = read_i16(reader) or_return
    description.x_min = read_i16(reader) or_return
    description.y_min = read_i16(reader) or_return
    description.x_max = read_i16(reader) or_return
    description.y_max = read_i16(reader) or_return

    return
}

coordinate_from_flag :: proc(reader: ^ByteReader, short: bool, same: bool) -> (i: i16, err: Font_Error) {
    if short {
        i = i16(read_u8(reader) or_return)
        i = i if same else -i
    } else {
        i = 0 if same else read_i16(reader) or_return
    }

    return
}

read_simple_glyph :: proc(glyph: ^Simple_Glyph, m_transformation: Maybe(Glyph_Transformation), description: Glyph_Description,  reader: ^ByteReader, allocator := context.allocator) -> Font_Error {
    number_of_contours := uint(description.number_of_contours)
    glyph.end_pts_of_contours = read_n_u16(reader, number_of_contours, allocator) or_return

    instruction_lengh := read_u16(reader) or_return
    glyph.instructions = read_n(reader, uint(instruction_lengh)) or_return

    point_count := uint(glyph.end_pts_of_contours[number_of_contours - 1] + 1)
    glyph.flags = make([]Simple_Glyph_Flags, point_count, allocator)
    glyph.x_coords = make([]f32, point_count, allocator)
    glyph.y_coords = make([]f32, point_count, allocator)

    count := point_count
    for count > 0 {
        defer count -= 1

        f := read_u8(reader) or_return
        flag := transmute(Simple_Glyph_Flags)(f)
        glyph.flags[point_count - count] = flag

        if .Repeat in flag {
            repeat_count := uint(read_u8(reader) or_return)
            count -= repeat_count

            for repeat_count > 0 {
                repeat_count -= 1
                glyph.flags[point_count - count - repeat_count] = flag
            }
        }
    }

    accX: i16 = 0
    for flag, index in glyph.flags {
        accX += coordinate_from_flag(reader, .X_Short in flag, .X_Same in flag) or_return
        glyph.x_coords[index] = f32(accX)// - description.x_min)
    }

    accY: i16 = 0
    for flag, index in glyph.flags {
        accY += coordinate_from_flag(reader, .Y_Short in flag, .Y_Same in flag) or_return
        glyph.y_coords[index] = f32(accY)// - description.y_min)
    }

    transformation := m_transformation.? or_else {
        1, 0, f32(-description.x_min),
        0, 1, f32(-description.y_min),
        0, 0,                  1,
    }

    for i in 0..<point_count {
        point3d :=  transformation * [3]f32 { glyph.x_coords[i], glyph.y_coords[i], 1 }

        glyph.x_coords[i] = point3d.x//, = i16(transformation[0][3] * (f32(glyph.x_coords[i]) * transformation[0][0] / transformation[0][3] + f32(glyph.y_coords[i]) * transformation[1][0] / transformation[0][3] + transformation[0][2]))
        glyph.y_coords[i] = point3d.y//i16(transformation[1][3] * (f32(glyph.x_coords[i]) * transformation[0][1] / transformation[1][3] + f32(glyph.y_coords[i]) * transformation[1][1] / transformation[1][3] + transformation[1][2]))
    }

    return nil
}

read_compound_glyph :: proc(glyph: ^Compound_Glyph, m_transformation: Maybe(Glyph_Transformation), description: Glyph_Description, reader: ^ByteReader, allocator := context.allocator) -> Font_Error {
    components, alloc_err := make([dynamic]Compound_Glyph_Component, 0, 4, allocator)
    transformation := m_transformation.? or_else {
        1, 0, f32(-description.x_min),
        0, 1, f32(-description.y_min),
        0, 0,                       1,
    }

    if alloc_err != nil {
        return .Out_Of_Memory
    }

    have_instructions := false
    for {
        component: Compound_Glyph_Component

        component.transformation = IDENTITY
        component.flag = transmute(Compound_Glyph_Flags)(read_u16(reader) or_return)
        component.index = read_u16(reader) or_return

        if .Are_Word in component.flag {
            component.transformation[0, 2] = f32((read_i16(reader) or_return))// - description.x_min)
            component.transformation[1, 2] = f32((read_i16(reader) or_return))// - description.y_min)
        } else {
            component.transformation[0, 2] = f32(i16(read_u8(reader) or_return))// - description.y_min)
            component.transformation[1, 2] = f32(i16(read_u8(reader) or_return))// - description.y_min)
        }

        if .Have_Scale in component.flag {
            short := f2dot14_f32(read_u16(reader) or_return)
            component.transformation[0, 0] = short
            component.transformation[1, 1] = short
        } else if .Have_XY_Scale in component.flag {
            component.transformation[0, 0] = f2dot14_f32(read_u16(reader) or_return)
            component.transformation[1, 1] = f2dot14_f32(read_u16(reader) or_return)
        } else if .Have_Two_By_Two in component.flag {
            component.transformation[0, 0] = f2dot14_f32(read_u16(reader) or_return)
            component.transformation[1, 0] = f2dot14_f32(read_u16(reader) or_return)
            component.transformation[0, 1] = f2dot14_f32(read_u16(reader) or_return)
            component.transformation[1, 1] = f2dot14_f32(read_u16(reader) or_return)
        }

        have_instructions = .Have_Instructions in component.flag

        component.transformation *= transformation

        append(&components, component)

        if .More_Components not_in component.flag {
            break
        }
    }

    if have_instructions {
        num_instructions := read_u16(reader) or_return
        glyph.instructions = read_n(reader, uint(num_instructions)) or_return
    }

    glyph.components = components[:]

    return nil
}

get_simple_glyph_contours :: proc(glyph: ^Simple_Glyph, allocator := context.allocator) -> (contours: []Contour, err: mem.Allocator_Error) {
    contours = make([]Contour, len(glyph.end_pts_of_contours), allocator) or_return
    line_points := make([dynamic]Point, 0, 20, allocator) or_return

    interpolations := 10
    point_start: u16 = 0
    for contour_index in 0..<len(glyph.end_pts_of_contours) {
        contour_end := glyph.end_pts_of_contours[contour_index] + 1
        contour_len := contour_end - point_start

        defer point_start = contour_end

        contour_xs := glyph.x_coords[point_start:contour_end]
        contour_ys := glyph.y_coords[point_start:contour_end]
        contour_flags := glyph.flags[point_start:contour_end]

        contour_points := make([dynamic]Point, 0, contour_len, allocator) or_return

        orientation_sum: i32 = 0
        point_index: u16 = 0
        total_count: u16 = 0
        for total_count < contour_len {
            defer clear(&line_points)

            for (.On_Curve not_in contour_flags[point_index]) {
                point_index = (point_index + 1) % contour_len
            }

            initial_x, initial_y := contour_xs[point_index], contour_ys[point_index]
            append(&line_points, Point { initial_x, initial_y })
            point_index = (point_index + 1) % contour_len

            for (.On_Curve not_in contour_flags[point_index]) {
                append(&line_points, Point { contour_xs[point_index], contour_ys[point_index] })
                point_index = (point_index + 1) % contour_len
            }

            final_x, final_y := contour_xs[point_index], contour_ys[point_index]
            append(&line_points, Point { final_x, final_y })
            line_len := u32(len(line_points))

            orientation_sum += i32(final_x - initial_x) * i32(final_y + initial_y) / 2

            total_count += u16(line_len) - 1

            if line_len == 2 {
                append(&contour_points, line_points[0])

                continue
            }

            delta := 1.0 / f32(interpolations)
            t: f32 = 0.0

            for _ in 0..<interpolations {
                defer t += delta
                point: Point

                for i in 0..<line_len {
                    point += pow(1.0 - t, line_len - 1 - i) * pow(t, i) * binomial(line_len - 1, i) * line_points[i]
                }

                append(&contour_points, point)
            }
        }

        orientation: Contour_Orientation = .Clockwise if orientation_sum > 0 else .CounterClockwise
        contours[contour_index] = Contour { contour_points[:], orientation }
    }

    return
}

get_compound_glyph_contours :: proc(glyph: ^Compound_Glyph, glyf: ^Glyf_Table, loca: ^Loca_Table, allocator := context.allocator) -> (contours: []Contour, err: mem.Allocator_Error) {
    contour_array := make([dynamic]Contour, 0, 10, allocator) or_return

    // total_height: u32 = 0
    // total_width: u32 = 0
    for component in glyph.components {
        inner_glyph: Glyph
        f_err: Font_Error
        width, height: u32

        if .Are_Values not_in component.flag {
            fmt.println("not implemented for component without values")
            return contours, .Out_Of_Memory
        }

        a := component.transformation[0, 0]
        c := component.transformation[0, 1]
        b := component.transformation[1, 0]
        d := component.transformation[1, 1]
        e := component.transformation[0, 2]
        f := component.transformation[1, 2]

        m0 := math.max(a, b)
        n0 := math.max(c, d)
        m := m0 if abs(abs(a) - abs(c)) > 33 / f32(u32(0xFFFF) + 1) else 2 * m0
        n := n0 if abs(abs(b) - abs(d)) > 33 / f32(u32(0xFFFF) + 1) else 2 * n0

        transformation := Glyph_Transformation {
            a, c, e * m,
            b, d, f * n,
            0, 0,      1,
        }

        if inner_glyph, width, height, f_err = get_glyph(glyf, transformation, loca, component.index, allocator); f_err != nil {
            return contours, .Out_Of_Memory
        }

        inner_glyph_contours := get_glyph_contours(&inner_glyph, glyf, loca, allocator) or_return

        append(&contour_array, ..inner_glyph_contours) or_return
    }

    contours = contour_array[:]

    return
}

get_glyph_contours :: proc(glyph: ^Glyph, glyf: ^Glyf_Table, loca: ^Loca_Table, allocator := context.allocator) -> (contours: []Contour, err: mem.Allocator_Error) {
    switch &f in glyph {
        case Simple_Glyph: contours = get_simple_glyph_contours(&f, allocator) or_return
        case Compound_Glyph: contours = get_compound_glyph_contours(&f, glyf, loca, allocator) or_return
    }

    return
}

contours_bitmap_write_line :: proc(bitmap: ^Contours_Bitmap, start, end: Point) {
    dp := end - start

    xcoef: f32 = 1
    ycoef: f32 = 1
    s: f32
    dmax: i32
    range: u32

    dxabs, dyabs := abs(dp.x), abs(dp.y)
    if dxabs > dyabs {
        ycoef = dp.y / dp.x
        v := i32(dp.x)
        sig: i32 = -1 if v < 0 else 1
        range = u32(v * sig)
        s = f32(sig)
    } else {
        xcoef = dp.x / dp.y
        v := i32(dp.y)
        sig: i32 = -1 if v < 0 else 1
        range = u32(v * sig)
        s = f32(sig)
    }

    for i in 0..=range {
        ii := f32(i) * s
        delta := Point { xcoef * ii, ycoef * ii }
        position := start + delta

        x := math.clamp(u32(math.round(position.x)), 0, bitmap.width - 1)
        y := math.clamp(u32(math.round(position.y)), 0, bitmap.height - 1) * bitmap.width

        bitmap.buffer[y + x] = 255
    }
}

find_matching_intersection :: proc(index: u32, intersections: []Contour_Intersection) -> (end: u32, use: bool) {
    for i in index + 1..<u32(len(intersections)) {
        if intersections[i].contour_orientation != intersections[index].contour_orientation {
            return u32(i), true
        }

        if intersections[i].contour_id != intersections[index].contour_id {
            continue
        }

        return u32(i), intersections[index].contour_orientation == .Clockwise && index % 2 == 0
    }

    return u32(len(intersections)), false
}

generate_contours_bitmap :: proc(bitmap: ^Contours_Bitmap, contours: []Contour, scale: f32 = 1.0, allocator := context.allocator) -> mem.Allocator_Error {
    bitmap.buffer = make([]u8, bitmap.width * bitmap.height, allocator) or_return
    intersections := make([dynamic]Contour_Intersection, 0, 20, allocator) or_return

    for y in 0..<bitmap.height {
        f_y := f32(y)
        defer clear(&intersections)

        for i in 0..<len(contours) {
            l := u32(len(contours[i].points))

            count: u32 = 0
            for count < l {
                defer count += 1

                prev := contours[i].points[count]
                next := contours[i].points[(count + 1) % l]
                current := next

                for current.y == f_y {
                    count += 1
                    current = contours[i].points[(count + 1) % l]
                }

                if (current.y <= f_y && prev.y <= f_y) || (current.y >= f_y && prev.y >= f_y) {
                    continue
                }

                intersection := Contour_Intersection {
                    contour_orientation = contours[i].orientation,
                    contour_id = u8(i),
                    x_coord = u32(prev.x + (f_y - prev.y) * (next.x - prev.x) / (next.y - prev.y)),
                }

                sorted_insert(&intersections, intersection) or_return
            }
        }

        line_offset := y * bitmap.width
        l := u32(len(intersections))
        i := u32(0)
        for i < l {
            end, use := find_matching_intersection(i, intersections[:])
            defer i = end

            if use {
                set(bitmap.buffer[line_offset + intersections[i].x_coord:line_offset + intersections[end].x_coord + 1], 255)
            }
        }
    }

    for i in 0..<len(contours) {
        for k in 0..<len(contours[i].points) {
            contours_bitmap_write_line(bitmap, contours[i].points[k], contours[i].points[(k + 1) % len(contours[i].points)])
        }
    }

    return nil
}

get_glyph_kind :: proc(number_of_contours: i16) -> (kind: Glyph, err: Font_Error) {
    if number_of_contours > 0 {
        kind = Simple_Glyph {}
    } else if number_of_contours < 0 {
        kind = Compound_Glyph {}
    } else {
        err = .Glyph_Not_Found
    }

    return
}

get_glyph :: proc(glyf: ^Glyf_Table, transformation: Maybe(Glyph_Transformation), loca: ^Loca_Table, index: u16, allocator := context.allocator) -> (glyph: Glyph, width: u32, height: u32, err: Font_Error) {
    offset := loca->f(index) or_return

    reader := reader_from_bytes(glyf.bytes[offset:])
    description := read_glyph_description(&reader) or_return
    glyph = get_glyph_kind(description.number_of_contours) or_return

    width = u32(description.x_max - description.x_min + 1)
    height = u32(description.y_max - description.y_min + 1)

    switch &g in glyph {
        case Simple_Glyph: read_simple_glyph(&g, transformation, description, &reader, allocator) or_return
        case Compound_Glyph: read_compound_glyph(&g, transformation, description, &reader, allocator) or_return
    }

    return
}

pow :: proc(f: f32, e: u32) -> f32 {
    x: f32 = 1

    count: u32 = e
    for count > 0 {
        defer count -= 1

        x *= f
    }

    return x
}
fac :: proc(number: u32) -> u32 {
    if number <= 1 {
        return 1
    }

    return fac(number - 1) * number
}

binomial :: proc(numerator: u32, denumerator: u32) -> f32 {
    n := fac(numerator)
    d := fac(denumerator)
    dif := fac(numerator - denumerator)

    return f32(n) / f32(d * dif)

}

set :: proc(bytes: []u8, b: u8) #no_bounds_check {
    for i in 0..<len(bytes) {
        bytes[i] = b
    }
}

sorted_insert :: proc(vec: ^[dynamic]Contour_Intersection, value: Contour_Intersection) -> mem.Allocator_Error {
    l := len(vec)
    reserve(vec, l + 1) or_return
    (^mem.Raw_Dynamic_Array)(vec).len += 1

    i: int = 0
    for i < l {
        if vec[i].x_coord > value.x_coord {
            break
        }

        i += 1
    }

    copy(vec[i+1:l+1], vec[i:l])
    vec[i] = value

    return nil
}

f2dot14_coef :: 1 / f32(0b00_11111111111111)
f2dot14_f32 :: proc(f: F2Dot14) -> f32 {
    return f32(f) * f2dot14_coef
    // fmt.printfln("reading: 0b{:16b}", f)
    // mask := ((f & 0b11_00000000000000) >> 14)
    // integer_abs := mask >> ((mask & 0b1) * ((mask & 0b10) >> 1))
    // // := f32(integer_abs)
    // frac := f & 0b00_11111111111111
    // s := i16((frac) >> 15) * -1

    // value := f32(i16(integer_abs * 0b01_00000000000000) + i16(frac) * s)
    // value *= f2dot14_coef
    // fmt.println("got", value)

    // fmt.printfln("in: 0b{:16b} -> f(0b{:16b}) -> i(0b{:16b}), abs(0b{:16b}), sign({:d})", f, frac, i, integer_abs, i16((f) >> 15) * -1)
    // return u16(i16(i) + i16(frac) * i16((frac) >> 15) * -1)
    // return value
}
// ABCDEFGHIJKLMNOPQRSTUVEXYZabcdefghijklmnopqrstuvexyz
