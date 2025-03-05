const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;
const TableDirectory = @import("table.zig").TableDirectory;

const Cmap = @import("cmap.zig").Cmap;
const Head = @import("head.zig").Head;
const MaxP = @import("maxp.zig").MaxP;
const Loca = @import("loca.zig").Loca;
const Glyf = @import("glyf.zig").Glyf;
const Hhea = @import("hhea.zig").Hhea;

const TableTag = enum  {
    @"cmap",
    @"glyf",
    @"head",
    @"hhea",
    @"loca",
    @"maxp",

    @"name",
    @"post",
    @"hmtx",

    fn new(tag: u32) ?TableTag {
        const bytes = std.mem.asBytes(&std.mem.nativeToBig(u32, tag));
        inline for (@typeInfo(TableTag).Enum.fields) |field| {
            if (std.mem.eql(u8, field.name, bytes)) {
                return @enumFromInt(field.value);
            }
        }

        return null;
    }
};

const OffsetTable = packed struct {
    scaler_type: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

pub fn main() !void {
    var initial_bytes: [1024]u8 = undefined;
    var intial_fixed_allocator = std.heap.FixedBufferAllocator.init(&initial_bytes);
    var args = try std.process.argsWithAllocator(intial_fixed_allocator.allocator());

    _ = args.next() orelse return error.MissingExeName;
    const megas = args.next() orelse return error.MissingMegaBytesToUse;
    const path = args.next() orelse return error.MissingArgument;
    const chars = args.next() orelse return error.MissingChars;

    const mbytes = try std.fmt.parseInt(u32, megas, 10);

    const bytes = try std.heap.page_allocator.alloc(u8, 1024 * 1024 * mbytes);
    var fixedAllocator = std.heap.FixedBufferAllocator.init(bytes);
    const allocator = fixedAllocator.allocator();

    const content = try readFile(path, allocator);

    var reader = ByteReader.new(content);

    const offset_table = reader.readType(OffsetTable);
    const tables = try reader.readTypeSlice(TableDirectory, offset_table.num_tables);
    var tables_mapping = std.EnumMap(TableTag, TableDirectory).init(.{});

    for (tables) |table| tables_mapping.put(TableTag.new(table.tag) orelse continue, table);

    const cmap = try Cmap.new(tables_mapping.get(.@"cmap") orelse return error.Cmap, content);
    const maxp = try MaxP.new(tables_mapping.get(.@"maxp") orelse return error.Maxp, content);
    const head = try Head.new(tables_mapping.get(.@"head") orelse return error.Head, content);
    const hhea = try Hhea.new(tables_mapping.get(.@"hhea") orelse return error.Hhea, content);
    const loca = try Loca.new(tables_mapping.get(.@"loca") orelse return error.Loca, head, content);
    var glyf = Glyf.new(tables_mapping.get(.@"glyf") orelse return error.Glyf, cmap, loca, maxp, content);

    const hmtx = tables_mapping.get(.@"hmtx") orelse return error.Hmtx;
    const name = tables_mapping.get(.@"name") orelse return error.Name;
    const post = tables_mapping.get(.@"post") orelse return error.Post;

    _ = hhea;
    _ = hmtx;
    _ = name;
    _ = post;

    var writerFixedAllocator = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, fixedAllocator.buffer.len - fixedAllocator.end_index - 20));
    const writer_allocator = writerFixedAllocator.allocator();

    for (chars) |c| {
        defer writerFixedAllocator.reset();

        const char: u8 = @intCast(c);
        std.debug.print("writing: {c} ", .{char});
        var file_path_array: [50]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&file_path_array, "images/{c}.ppm", .{char});

        try write_to_file(file_path, try write_to_buffer(&glyf, char, writer_allocator));
    }
}

const flag = true;

pub fn write_to_buffer(glyf: *Glyf, char: u8, allocator: std.mem.Allocator) ![]u8 {
    const start = try std.time.Instant.now();
    const glyph = try glyf.get(char, allocator);
    const glyph_end = try std.time.Instant.now();
    const buffer = try allocator.alloc(u8, glyph.bitmap.len * (3 * 3 + 3) + 100);

    const height: u32 = @intFromFloat(glyph.height);
    const width: u32 = @intFromFloat(glyph.width);

    const header = try std.fmt.bufPrint(buffer, "P3\n{} {}\n255\n", .{width, height});
    var len: usize = header.len;

    for (0..height) |y| {
        for (0..width) |x| {
            const b = glyph.bitmap[(height - y - 1) * width + x];
            const writer = try std.fmt.bufPrint(buffer[len..], "{} {} {}\n", .{b, b, b});
            len += writer.len;
        }
    }

    const end = try std.time.Instant.now();
    std.debug.print("glyph: {} ns, total: {} ns\n", .{glyph_end.since(start), end.since(start)});

    // _ = &len;
    // _ = start;
    // _ = glyph_end;
    return buffer[0..len];
}

pub fn write_to_file(path: []const u8, buffer: []u8) !void {
    if (flag) {
        const file = std.fs.cwd().createFile(path, .{}) catch return error.Open;
        defer file.close();
        try file.writeAll(buffer);
    }
}

pub fn readFile(path: []const u8, allocator: std.mem.Allocator) error{Read, Seek, Open, OutOfMemory}![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.Open;
    defer file.close();

    const end = file.getEndPos() catch return error.Seek;
    const content = try allocator.alloc(u8, end);

    var count = end;

    while (count > 0) {
        const len = file.read(content[end - count..]) catch return error.Read;
        defer count -= len;

        if (len == 0) break; }

    if (count != 0) return error.Read;

    return content;
}
