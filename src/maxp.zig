const TableDirectory = @import("table.zig").TableDirectory;
const ByteReader = @import("reader.zig").ByteReader;
const Fixed = @import("fixed.zig").Fixed;

pub const MaxP = packed struct {
    version: Fixed,
    num_glyphs: u16,
    max_points: u16,
    max_contours: u16,
    max_component_points: u16,
    max_component_contours: u16,
    max_zones: u16,
    max_twilight_points: u16,
    max_storage: u16,
    max_function_defs: u16,
    max_instruction_defs: u16,
    max_stack_elements: u16,
    max_size_of_instructions: u16,
    max_component_elements: u16,
    max_component_depth: u16,

    pub fn new(table: TableDirectory, bytes: []u8) error{Version}!MaxP {
        var reader = ByteReader.new(bytes[table.offset..]);
        const self = reader.readType(MaxP);

        if (self.version.float != 0 or self.version.int != 1) return error.Version;
        return self;
    }
};
