const ByteReader = @import("reader.zig").ByteReader;
const TableDirectory = @import("table.zig").TableDirectory;
const Fixed = @import("fixed.zig").Fixed;

pub const Head = packed struct {
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

    pub fn new(table: TableDirectory, bytes: []u8) error{Version, Magic}!Head {
        var reader = ByteReader.new(bytes[table.offset..], null);
        const self = reader.readType(Head);

        if (self.version.float != 0 or self.version.int != 1) return error.Version;
        if (self.magic_number != 0x5F0F3CF5) return error.Magic;

        return self;
    }
};
