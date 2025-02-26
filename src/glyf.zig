const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;

const TableDirectory = @import("table.zig").TableDirectory;
const Loca = @import("loca.zig").Loca;
const Cmap = @import("cmap.zig").Cmap;
const MaxP = @import("maxp.zig").MaxP;

const GlyphDescription = packed struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

pub const Glyf = struct {
    table: TableDirectory,
    loca: Loca,
    cmap: Cmap,
    maxp: MaxP,
    bytes: []u8,

    pub fn new(table: TableDirectory, cmap: Cmap, loca: Loca, maxp: MaxP, bytes: []u8) Glyf {
        return .{
            .table = table,
            .loca = loca,
            .cmap = cmap,
            .maxp = maxp,
            .bytes = bytes[table.offset..],
        };
    }

    pub fn get(self: Glyf, char: u16) void {
        const c: u8 = @intCast(char);
        const index = self.cmap.get_index(char) orelse 0;

        std.debug.assert(index <= self.maxp.num_glyphs);

        const offset: u32 = self.loca.readF(&self.loca, index);

        var glyph_reader = ByteReader.new(self.bytes, null);
        const glyph = glyph_reader.readTypeFromAbsoluteOffset(GlyphDescription, offset);

        std.debug.print("{c} index: {}, contours: {}, offset: {}\n", .{c, index, glyph.number_of_contours, offset});
    }
};

