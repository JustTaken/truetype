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
    const glyf = Glyf.new(tables_mapping.get(.@"glyf") orelse return error.Glyf, cmap, loca, maxp, content, allocator);

    const hmtx = tables_mapping.get(.@"hmtx") orelse return error.Hmtx;
    const name = tables_mapping.get(.@"name") orelse return error.Name;
    const post = tables_mapping.get(.@"post") orelse return error.Post;

    _ = hhea;
    _ = hmtx;
    _ = name;
    _ = post;

    // for ('A'..'B') |c| {
    try glyf.get(@intCast('A'));
    // }
}

fn readFile(path: []const u8, allocator: std.mem.Allocator) error{Read, Seek, Open, OutOfMemory}![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.Open;
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
