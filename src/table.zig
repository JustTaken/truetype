pub const TableDirectory = extern struct {
    tag: [4]u8,
    checkSum: u32,
    offset: u32,
    length: u32,
};


