const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;

const TableDirectory = @import("table.zig").TableDirectory;
const Loca = @import("loca.zig").Loca;
const Cmap = @import("cmap.zig").Cmap;
const MaxP = @import("maxp.zig").MaxP;

const GlyphKind = enum(i16) {
    Simple,
    Compound,
    None,

    fn new(int: i16) GlyphKind {
        if (int < 0) return .Compound;
        if (int == 0) return .None;
        return .Simple;
    }
};

const GlyphDescription = packed struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

const SimpleGlyph = struct {
    outlines: []Outline,

    const Outline = struct {
        points: []Point,
        on_curve: []bool,
    };

    const Point = struct {
        x: i16,
        y: i16,
    };

    const Flag = packed struct {
        on_curve: bool,
        x_short_vector: bool,
        y_short_vector: bool,
        repeat: bool,
        x_is_same: bool,
        y_is_same: bool,
        reserved0: bool,
        reserved1: bool,
    };

    fn coordinate_from_flag(reader: *ByteReader, short: bool, same: bool) i16 {
        if (short) {
            const value: i16 = @intCast(reader.readValue(u8));

            return if (same) value else -value;
        }

        return if (same) 0 else reader.readValue(i16);
    }

    pub fn new(
        description: GlyphDescription,
        reader: *ByteReader,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!SimpleGlyph {
        var self: SimpleGlyph = undefined;

        const number_of_contours: u16 = @intCast(description.number_of_contours);
        self.outlines = try allocator.alloc(Outline, number_of_contours);

        const end_pts_of_contours = try reader.readSlice(u16, number_of_contours);

        const instructionLength = reader.readValue(u16);
        const instructions = try reader.readSlice(u8, instructionLength);
        _ = instructions;

        const point_count = end_pts_of_contours[number_of_contours - 1] + 1;

        const coodinate_points = try allocator.alloc(Point, point_count);
        const on_curve = try allocator.alloc(bool, point_count);

        const flags = try allocator.alloc(Flag, point_count);
        defer allocator.free(flags);

        var count = point_count;
        while (count > 0) {
            const flag: Flag = @bitCast(reader.readValue(u8));

            flags[point_count - count] = flag;

            if (flag.repeat) {
                var repeat_count = reader.readValue(u8);
                count -= repeat_count;

                while (repeat_count > 0) {
                    flags[point_count - count - repeat_count] = flag;
                    repeat_count -= 1;
                }
            }

            count -= 1;
        }

        var accX: i16 = 0;
        for (flags, 0..) |flag, i| {
            accX += coordinate_from_flag(reader, flag.x_short_vector, flag.x_is_same);
            coodinate_points[i].x = accX;

            on_curve[i] = flag.on_curve;
        }

        var accY: i16 = 0;
        for (flags, 0..) |flag, i| {
            accY += coordinate_from_flag(reader, flag.y_short_vector, flag.y_is_same);
            coodinate_points[i].y = accY;
        }

        count = 0;
        for (self.outlines, 0..) |*outline, i| {
            const end = end_pts_of_contours[i] + 1;

            outline.points = coodinate_points[count..end];
            outline.on_curve = on_curve[count..end];

            count = end;
            std.debug.print("{any}\n", .{outline.points});
        }

        return self;
    }
};
// const CompoudGlyph = packed struct {

// };

pub const Glyf = struct {
    table: TableDirectory,
    loca: Loca,
    cmap: Cmap,
    maxp: MaxP,
    bytes: []u8,
    allocator: std.mem.Allocator,

    pub fn new(
        table: TableDirectory,
        cmap: Cmap,
        loca: Loca,
        maxp: MaxP,
        bytes: []u8,
        allocator: std.mem.Allocator,
    ) Glyf {
        return .{
            .table = table,
            .loca = loca,
            .cmap = cmap,
            .maxp = maxp,
            .bytes = bytes[table.offset..],
            .allocator = allocator,
        };
    }

    pub fn get(self: Glyf, char: u16) error{OutOfMemory}!void {
        const index = self.cmap.get_index(char) orelse 0;

        std.debug.assert(index <= self.maxp.num_glyphs);

        const offset: u32 = self.loca.readF(&self.loca, index);

        var glyph_reader = ByteReader.new(self.bytes[offset..]);
        const glyph_description = glyph_reader.readType(GlyphDescription);

        switch (GlyphKind.new(glyph_description.number_of_contours)) {
            .Simple => {
                const glyph = try SimpleGlyph.new(glyph_description, &glyph_reader, self.allocator);
                _ = glyph;
            },
            .Compound => unreachable,
            .None => unreachable,
        }

    }
};
