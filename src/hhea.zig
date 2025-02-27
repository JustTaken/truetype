const Fixed = @import("fixed.zig").Fixed;
const TableDirectory = @import("table.zig").TableDirectory;
const ByteReader = @import("reader.zig").ByteReader;

pub const Hhea = packed struct {
    version: Fixed,
    ascent: i16,
    descent: i16,
    line_gap: i16,
    advance_width_max: u16,
    min_left_side_bearing: i16,
    min_right_side_bearing: i16,
    x_max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    reserved0: i16,
    reserved1: i16,
    reserved2: i16,
    reserved3: i16,
    metric_data_format: i16,
    num_of_long_hor_metrics: u16,

    pub fn new(table: TableDirectory, bytes: []u8) error{Version, Read}!Hhea {
        var reader = ByteReader.new(bytes[table.offset..]);
        const self = reader.readType(Hhea);

        if (self.version.float != 0 or self.version.int != 1) return error.Version;
        if (self.reserved0 != 0) return error.Read;
        if (self.reserved1 != 0) return error.Read;
        if (self.reserved2 != 0) return error.Read;
        if (self.reserved3 != 0) return error.Read;

        return self;
    }
};

