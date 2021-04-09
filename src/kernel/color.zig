pub const Color = enum(u32) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGrey = 7,
    DarkGrey = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 0xFFFFFF,
};

pub fn R(c: Color) u8 {
    return @truncate(u8, @enumToInt(c) >> 16);
}

pub fn G(c: Color) u8 {
    return @truncate(u8, @enumToInt(c) >> 8);
}

pub fn B(c: Color) u8 {
    return @truncate(u8, @enumToInt(c));
}
