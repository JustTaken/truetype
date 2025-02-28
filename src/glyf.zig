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
    bitmap: []u8,
    width: u32,
    height: u32,

    const Point = struct {
        x: i16,
        y: i16,

        fn scale(self: Point, n: usize) Point {
            const i_n: i16 = @intCast(n);
            return .{
                .x = @divFloor(self.x, i_n),
                .y = @divFloor(self.y, i_n),
            };
        }

        fn shift(self: Point, x: i16, y: i16) Point {
            return .{
                .x = self.x + x,
                .y = self.y + y,
            };
        }
    };

    const Bezier = struct {
        points: []Point,
        len: usize,

        fn plot(points: []Point, on_curve: []bool, interpolations: u32, allocator: std.mem.Allocator) error{OutOfMemory}![]Point {
            var self: Bezier = undefined;
            self.points = try allocator.alloc(Point, points.len * 3);
            self.len = 0;

            const line_points = try allocator.alloc(Point, 20);
            defer allocator.free(line_points);

            var i: usize = 0;
            var total_count: usize = 0;
            while (total_count < points.len) {
                while (!on_curve[i]) : (i = (i + 1) % points.len) {}

                var point_count: u32 = 0;

                line_points[0] = points[i];
                point_count += 1;

                i = (i + 1) % points.len;

                while (!on_curve[i]) {
                    line_points[point_count] = points[i];
                    point_count += 1;
                    i = (i + 1) % points.len;
                }

                line_points[point_count] = points[i];
                point_count += 1;

                self.interpolate(line_points[0..point_count], interpolations);

                total_count += point_count - 1;
            }

            return self.points[0..self.len];
        }

        fn interpolate(self: *Bezier, points: []Point, interpolations: u32) void {
            if (points.len == 2) {
                self.insert_point(points[0]);

                return;
            }

            const delta: f32 = 1.0 / @as(f32, @floatFromInt(interpolations));
            const n = points.len - 1;

            var t: f32 = 0.0;
            for (0..interpolations) |_| {
                defer t += delta;

                var point = Point { .x = 0, .y = 0};

                for (0..points.len) |i| {
                    const fs = calculate_sum(t, @intCast(n - i), @intCast(i), binomial(n, i), points[i]);

                    point.x += @intFromFloat(fs[0]);
                    point.y += @intFromFloat(fs[1]);
                }

                self.insert_point(point);
            }
        }

        fn insert_point(self: *Bezier, point: Point) void {
            defer self.len += 1;
            self.points[self.len] = point;
        }

        fn calculate_sum(t: f32, t_neg_exp: u32, t_exp: u32, cof: f32, point: Point) [2]f32 {
            const t_exp_neg_result = std.math.pow(f32, (1 - t), @floatFromInt(t_neg_exp));
            const t_exp_result = std.math.pow(f32, t, @floatFromInt(t_exp));
            const f_x: f32 = @floatFromInt(point.x);
            const f_y: f32 = @floatFromInt(point.y);

            const mult = t_exp_neg_result * t_exp_result * cof;

            return .{ mult * f_x, mult * f_y };
        }
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
        self.width = @as(u32, @intCast(description.x_max - description.x_min)) / DIV + 1;
        self.height = @as(u32, @intCast(description.y_max - description.y_min)) / DIV + 1;

        print("width: {}, height: {}\n", .{self.width, self.height});
        self.bitmap = try allocator.alloc(u8, self.width * self.height);
        @memset(self.bitmap, 0);

        const number_of_contours: u16 = @intCast(description.number_of_contours);
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
        for (0..number_of_contours) |i| {
            const end = end_pts_of_contours[i] + 1;

            defer count = end;

            const outline = try Bezier.plot(coodinate_points[count..end], on_curve[count..end], 4, allocator);

            for (0..outline.len) |k| {
                self.writeDot(outline[k].shift(-description.x_min, -description.y_min).scale(DIV), MAX_RAD);
                self.writeLine(outline[k].shift(-description.x_min, -description.y_min).scale(DIV), outline[(k + 1) % outline.len].shift(-description.x_min, -description.y_min).scale(DIV));
            }
        }

        return self;
    }

    const DIV: u16 = 2;
    const MAX_RAD: u32 = 3;

    fn writeDot(self: *SimpleGlyph, pos: Point, rad: u32) void {
        print("pos: ({}, {})\n", .{pos.x, pos.y});

        self.addAndWrite(pos.x, pos.y, 0, 0, 255);
        for (1..rad + 1) |r| {
            const i_r: i32 = @intCast(r);

            self.addAndWrite(pos.x, pos.y, i_r, 0, 255);
            self.addAndWrite(pos.x, pos.y, -i_r, 0, 255);

            self.addAndWrite(pos.x, pos.y, 0, i_r, 255);
            self.addAndWrite(pos.x, pos.y, 0, -i_r, 255);
            for (1..r + 1) |k| {
                const ii: i32 = @intCast(k);

                self.addAndWrite(pos.x, pos.y, i_r, ii, 255);
                self.addAndWrite(pos.x, pos.y, i_r, -ii, 255);
                self.addAndWrite(pos.x, pos.y, -i_r, ii, 255);
                self.addAndWrite(pos.x, pos.y, -i_r, -ii, 255);

                self.addAndWrite(pos.x, pos.y, ii, i_r, 255);
                self.addAndWrite(pos.x, pos.y, -ii, i_r, 255);
                self.addAndWrite(pos.x, pos.y, ii, -i_r, 255);
                self.addAndWrite(pos.x, pos.y, -ii, -i_r, 255);
            }
        }

        print("\n", .{});
    }

    fn writeLine(self: *SimpleGlyph, first: Point, second: Point) void {
        const Independent = enum { X, Y };

        const dx = second.x - first.x;
        const dy = second.y - first.y;

        if (dx == 0 and dy == 0) return;


        var coef: f32 = undefined;
        const ind: Independent = if (abs(dx) > abs(dy)) .X else .Y;
        coef = if (ind == .X) @as(f32, @floatFromInt(dy)) / @as(f32, @floatFromInt(dx)) else @as(f32, @floatFromInt(dx)) / @as(f32, @floatFromInt(dy));

        const d_max = max(dx, dy);
        const sig: i32 = if (d_max > 0) 1 else -1;

        for (0..abs(d_max)) |i| {
            const ii = @as(i32, @intCast(i)) * sig;

            const deltaX: i32 = if (ind == .X) ii else @intFromFloat(@as(f32, @floatFromInt(ii)) * coef);
            const deltaY: i32 = if (ind == .Y) ii else @intFromFloat(@as(f32, @floatFromInt(ii)) * coef);

            self.addAndWrite(first.x, first.y, deltaX, deltaY, 255);
        }
    }

    fn addAndWrite(self: *SimpleGlyph, x: i32, y: i32, deltaX: i32, deltaY: i32, b: u8) void {
        const r_x = x + deltaX;
        const r_y = y + deltaY;

        if (r_x < 0 or r_y < 0 or r_y >= self.height or r_x >= self.width) {
            print("!({} {}), ", .{r_x, r_y});
            return;
        }
        print("({} {}), ", .{r_x, r_y});

        const u_x: u32 = @intCast(r_x);
        const u_y: u32 = @intCast(r_y);

        self.bitmap[u_y * self.width + u_x] = b;
    }
};

pub const Glyf = struct {
    table: TableDirectory,
    loca: Loca,
    cmap: Cmap,
    maxp: MaxP,
    bytes: []u8,
    allocator: std.heap.FixedBufferAllocator,

    pub fn new(
        table: TableDirectory,
        cmap: Cmap,
        loca: Loca,
        maxp: MaxP,
        bytes: []u8,
        allocator: std.heap.FixedBufferAllocator,
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

    pub fn get(self: *Glyf, char: u16) error{OutOfMemory}!SimpleGlyph {
        self.allocator.reset();

        const index = self.cmap.get_index(char) orelse 0;

        std.debug.assert(index <= self.maxp.num_glyphs);

        const offset: u32 = self.loca.readF(&self.loca, index);

        var glyph_reader = ByteReader.new(self.bytes[offset..]);
        const glyph_description = glyph_reader.readType(GlyphDescription);

        switch (GlyphKind.new(glyph_description.number_of_contours)) {
            .Simple => return try SimpleGlyph.new(glyph_description, &glyph_reader, self.allocator.allocator()),
            .Compound => unreachable,
            .None => unreachable,
        }

    }
};

fn binomial(numerator: usize, denumerator: usize) f32 {
    const n = fac(numerator);
    const d = fac(denumerator);
    const dif = fac(numerator - denumerator);

    const f_numerator: f32 = @floatFromInt(n);
    const f_denumerator: f32 = @floatFromInt(d * dif);

    return f_numerator / f_denumerator;
}

fn fac(number: usize) usize {
    if (number <= 1) return 1;
    return fac(number - 1) * number;
}

fn print(comptime fmt: []const u8, args: anytype) void {
    const do_print = false;
    if (!do_print) return;
    std.debug.print(fmt, args);
}

fn max(first: isize, second: isize) isize {
    return if (abs(first) > abs(second)) first else second;
}

fn abs(number: isize) usize {
    return if (number < 0) @intCast(-number) else @intCast(number);
}
