const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;
const TableDirectory = @import("table.zig").TableDirectory;

const Loca = @import("loca.zig").Loca;
const Cmap = @import("cmap.zig").Cmap;
const MaxP = @import("maxp.zig").MaxP;

const Fixed = @import("fixed.zig").FFloat;
// const Fixed = @import("fixed.zig").Fixed;
const ZERO = Fixed.new(0, false, 0);

const DIV: u16 = 1;
const MAX_RAD: u32 = 3;
const INTERPOLATIONS: u32 = 10;
const FILL_BYTE: u8 = 255;

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
    width: f32,
    height: f32,

    const Point = @Vector(2, f32);

    const Orientation = enum {
        Clockwise,
        CounterClockwise,
    };

    const Bezier = struct {
        fn contourOutline(
            xs: []i16,
            ys: []i16,
            on_curve: []bool,
            interpolations: u32,
            allocator: std.mem.Allocator,
        ) error{OutOfMemory}![]Point {
            var line_points = try std.ArrayList(Point).initCapacity(allocator, 20);
            var points = try std.ArrayList(Point).initCapacity(allocator, xs.len);

            var i: usize = 0;
            var total_count: usize = 0;
            while (total_count < xs.len) {
                while (!on_curve[i]) : (i = (i + 1) % xs.len) {}

                line_points.clearRetainingCapacity();

                try line_points.append(Point { @floatFromInt(xs[i]), @floatFromInt(ys[i]) });

                i = (i + 1) % xs.len;

                while (!on_curve[i]) {
                    try line_points.append(Point {@floatFromInt(xs[i]), @floatFromInt(ys[i])});
                    i = (i + 1) % xs.len;
                }

                try line_points.append(Point { @floatFromInt(xs[i]), @floatFromInt(ys[i]) });

                try interpolate(&points, line_points.items, interpolations);

                total_count += line_points.items.len - 1;
            }

            return points.items;
        }

        fn interpolate(points: *std.ArrayList(Point), raw_points: []Point, interpolations: u32) error{OutOfMemory}!void {
            if (raw_points.len == 2) {
                try points.append(raw_points[0]);

                return;
            }

            const delta: f32 = 1.0 / @as(f32, @floatFromInt(interpolations));
            const n = raw_points.len - 1;

            var t: f32 = 0.0;
            for (0..interpolations) |_| {
                defer t += delta;

                var point = Point{ 0, 0 };

                for (0..raw_points.len) |i| {
                    const mul = pow(1 - t, n - i) * pow(t, i) * binomial(n, i);
                    point += Point { mul * raw_points[i][0], mul * raw_points[i][1] };
                }

                try points.append(point);
            }
        }

        // fn findXIntersections(curve: []Point, height: f32, allocator: std.mem.Allocator) error{OutOfMemory}![]i16 {
        //     var intersections = try std.ArrayList(i16).initCapacity(allocator, 10);

        //     return intersections.items;
        // }

        fn contourOrientation(outline: []Point) Orientation {
            var sum: i32 = 0;
            for (0..outline.len) |i| {
                const current = outline[i];
                const next = outline[(i + 1) % outline.len];
                const y: i32 = @intFromFloat((next[1] + current[1]) / 2);
                const xdif: i32 = @intFromFloat(next[0] - current[0]);

                sum += y * xdif;
            }

            return if (sum > 0) .Clockwise else .CounterClockwise;
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

    fn coordinateFromFlag(reader: *ByteReader, short: bool, same: bool) i16 {
        return switch (short) {
            true => switch (same) {
                true => @intCast(reader.readValue(u8)),
                false => -@as(i16, @intCast(reader.readValue(u8))),
            },
            false => switch (same) {
                true => 0,
                false => reader.readValue(i16),
            },
        };
    }

    pub fn new(
        description: GlyphDescription,
        reader: *ByteReader,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!SimpleGlyph {
        var self: SimpleGlyph = undefined;

        self.width = @floatFromInt(description.x_max - description.x_min + 1);
        self.height = @floatFromInt(description.y_max - description.y_min + 1);
        self.bitmap = try allocator.alloc(u8, @intFromFloat(self.width * self.height));

        @memset(self.bitmap, 0);

        const number_of_contours: u16 = @intCast(description.number_of_contours);
        const end_pts_of_contours = try reader.readSlice(u16, number_of_contours);

        const instructionLength = reader.readValue(u16);
        const instructions = try reader.readSlice(u8, instructionLength);
        _ = instructions;

        const point_count = end_pts_of_contours[number_of_contours - 1] + 1;

        const on_curve = try allocator.alloc(bool, point_count);

        const flags = try allocator.alloc(Flag, point_count);
        defer allocator.free(flags);

        var count = point_count;
        while (count > 0) {
            const flag: Flag = @bitCast(reader.readValue(u8));

            flags[point_count - count] = flag;
            std.debug.assert(!flag.reserved0 and !flag.reserved1);

            if (flag.repeat) {
                var repeat_count = reader.readValue(u8);
                count -= repeat_count;

                while (repeat_count > 0) {
                    repeat_count -= 1;
                    flags[point_count - count - repeat_count] = flag;
                }
            }

            count -= 1;
        }

        const coordinate_xs = try allocator.alloc(i16, point_count);
        const coordinate_ys = try allocator.alloc(i16, point_count);

        var accX: i16 = 0;
        for (flags, 0..) |flag, i| {
            accX += coordinateFromFlag(reader, flag.x_short_vector, flag.x_is_same);
            coordinate_xs[i] = accX - description.x_min;

            on_curve[i] = flag.on_curve;
        }

        var accY: i16 = 0;
        for (flags, 0..) |flag, i| {
            accY += coordinateFromFlag(reader, flag.y_short_vector, flag.y_is_same);
            coordinate_ys[i] = accY - description.y_min;
        }

        const contours = try allocator.alloc([]Point, number_of_contours);
        const orientations = try allocator.alloc(Orientation, number_of_contours);

        count = 0;
        for (0..number_of_contours) |i| {
            const end = end_pts_of_contours[i] + 1;

            defer count = end;

            contours[i] = try Bezier.contourOutline(
                coordinate_xs[count..end],
                coordinate_ys[count..end],
                on_curve[count..end],
                INTERPOLATIONS,
                allocator,
            );

            orientations[i] = Bezier.contourOrientation(contours[i]);

            for (0..contours[i].len) |k| {
                self.writeLine(contours[i][k], contours[i][(k + 1) % contours[i].len], FILL_BYTE);
            }
        }

        // var fixedAllocator = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 1024));
        // const curveAllocator = fixedAllocator.allocator();

        var intersections = try std.ArrayList(u32).initCapacity(allocator, 30);
        const self_height: u32 = @intFromFloat(self.height);

        for (0..self_height) |y| {
            defer intersections.clearRetainingCapacity();
            const f_y: f32 = @floatFromInt(y);

            for (0..number_of_contours) |i| {
                const contour = contours[i];

                count = 0;
                while (count < contour.len) : (count += 1) {
                    const prev = contour[count];
                    const next = contour[(count + 1) % contour.len];
                    var current = next;

                    while (current[1] == f_y) {
                        count += 1;
                        current = contour[(count + 1) % contour.len];
                    }

                    if ((current[1] <= f_y and prev[1] <= f_y) or (current[1] >= f_y and prev[1] >= f_y)) continue;

                    const coef = (next[0] - prev[0]) / (next[1] - prev[1]);

                    try sorted_insert(&intersections, @intFromFloat(prev[0] + coef * (f_y - prev[1])));
                }
            }

            const height = y * @as(u32, @intFromFloat(self.width));
            for (0..intersections.items.len / 2) |x| {
                const index = x * 2;

                @memset(self.bitmap[height + intersections.items[index]..height + intersections.items[index + 1] + 1], FILL_BYTE);
            }
        }

        return self;
    }

    fn writeLine(self: *SimpleGlyph, first: Point, second: Point, alpha: u8) void {
        const dp = second - first;

        // if (dp[0] == 0 and dp[1] == 0) return;

        const dx_int: i32 = @intFromFloat(dp[0]);
        const dy_int: i32 = @intFromFloat(dp[1]);
        var xcoef: f32 = 1.0;
        var ycoef: f32 = 1.0;
        var range: u32 = undefined;
        var s: f32 = undefined;

        if (abs(dx_int) > abs(dy_int)) {
            const sig = sign(dx_int);
            ycoef = dp[1] / dp[0];
            range = @intCast(dx_int * sig);
            s = @floatFromInt(sig);
        } else {
            const sig = sign(dy_int);
            xcoef = dp[0] / dp[1];
            range = @intCast(dy_int * sig);
            s = @floatFromInt(sig);
        }

        for (0..range + 1) |i| {
            const ii = @as(f32, @floatFromInt(i)) * s;
            const delta = Point { xcoef * ii, ycoef * ii };

            const pos = first + delta;

            const width: u32 = @intFromFloat(std.math.clamp(pos[0], 0, self.width));
            const height = @as(u32, @intFromFloat(std.math.clamp(pos[1], 0, self.height))) * @as(u32, @intFromFloat(self.width));

            self.bitmap[height + width] = alpha;
        }
    }
};

pub const Glyf = struct {
    table: TableDirectory,
    loca: Loca,
    cmap: Cmap,
    maxp: MaxP,
    bytes: []u8,

    pub fn new(
        table: TableDirectory,
        cmap: Cmap,
        loca: Loca,
        maxp: MaxP,
        bytes: []u8,
    ) Glyf {
        return .{
            .table = table,
            .loca = loca,
            .cmap = cmap,
            .maxp = maxp,
            .bytes = bytes[table.offset..],
        };
    }

    pub fn get(self: *Glyf, char: u16, allocator: std.mem.Allocator) error{OutOfMemory}!SimpleGlyph {
        const index = self.cmap.get_index(char) orelse 0;

        std.debug.assert(index <= self.maxp.num_glyphs);

        const offset: u32 = self.loca.readF(&self.loca, index);

        var glyph_reader = ByteReader.new(self.bytes[offset..]);
        const glyph_description = glyph_reader.readType(GlyphDescription);

        switch (GlyphKind.new(glyph_description.number_of_contours)) {
            .Simple => return try SimpleGlyph.new(glyph_description, &glyph_reader, allocator),
            .Compound => unreachable,
            .None => unreachable,
        }
    }
};

fn sorted_insert(array: *std.ArrayList(u32), value: u32) error{OutOfMemory}!void {
    var i: u32 = 0;
    while (i < array.items.len) {
        if (array.items[i] > value) break;
        i += 1;
    }

    try array.insert(i, value);
}

fn binomial(numerator: usize, denumerator: usize) f32 {
    const n = fac(numerator);
    const d = fac(denumerator);
    const dif = fac(numerator - denumerator);

    return @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(d * dif));
}

fn fac(number: usize) usize {
    if (number <= 1) return 1;
    return fac(number - 1) * number;
}

fn max(first: isize, second: isize) isize {
    return if (abs(first) > abs(second)) first else second;
}

fn abs(number: isize) usize {
    return if (number < 0) @intCast(-number) else @intCast(number);
}

fn sign(number: isize) isize {
    return if (number < 0) -1 else 1;
}

fn less(_: @TypeOf(.{}), first: i16, second: i16) bool {
    return first < second;
}

fn pow(f: f32, n: usize) f32 {
    var float: f32 = 1;

    var count = n;
    while (count > 0) {
        float *= f;
        count -= 1;
    }

    return float;
}
