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
    const bytes = try std.heap.page_allocator.alloc(u8, 1024 * 1024 * 20);
    var fixedAllocator = std.heap.FixedBufferAllocator.init(bytes);
    const allocator = fixedAllocator.allocator();

    const content = try readFile("assets/hack.ttf", allocator);

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
    var glyf = Glyf.new(tables_mapping.get(.@"glyf") orelse return error.Glyf, cmap, loca, maxp, content, std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 3 * 1024 * 1024)));

    const hmtx = tables_mapping.get(.@"hmtx") orelse return error.Hmtx;
    const name = tables_mapping.get(.@"name") orelse return error.Name;
    const post = tables_mapping.get(.@"post") orelse return error.Post;

    _ = hhea;
    _ = hmtx;
    _ = name;
    _ = post;

    try write(&glyf, 'B');
}

fn write(glyf: *Glyf, char: u8) !void {
    const glyph = try glyf.get(char);

    const flag = false;

    if (flag) {
        for (0..glyph.height) |y| {
            for (0..glyph.width) |x| {
                const b = glyph.bitmap[y * glyph.width + x];
                if (b == 0) continue;

                std.debug.print("{d} ", .{b});
            }
            std.debug.print("\n", .{});
        }
    } else {
        const file = std.fs.cwd().createFile("assets/output.ppm", .{}) catch return error.Open;
        defer file.close();

        var buffer: [100]u8 = undefined;
        const header = try std.fmt.bufPrint(&buffer, "P3\n{} {}\n255\n", .{glyph.width, glyph.height});
        try file.writeAll(header);

        for (glyph.bitmap) |b| {
            const writer = try std.fmt.bufPrint(&buffer, "{} {} {}\n", .{b, b, b});
            try file.writeAll(writer);
        }
    }
}

fn readFile(path: []const u8, allocator: std.mem.Allocator) error{Read, Seek, Open, OutOfMemory}![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.Open;
    defer file.close();

    const end = file.getEndPos() catch return error.Seek;
    const content = try allocator.alloc(u8, end);

    var count = end;

    while (count > 0) {
        const len = file.read(content[end - count..]) catch return error.Read;
        defer count -= len;

        if (len == 0) break;
    }

    if (count != 0) return error.Read;

    return content;
}
