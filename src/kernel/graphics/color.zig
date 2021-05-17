pub const Black = 0;
pub const Blue = 0x0000ff;
pub const Green = 0x008000;
pub const Cyan = 0x00ffff;
pub const Red = 0xff0000;
pub const Magenta = 0xff00ff;
pub const Brown = 0xa52a2a;
pub const LightGrey = 0xd3d3d3;
pub const DarkGrey = 0xa9a9a9;
pub const LightBlue = 0xadd8e6;
pub const LightGreen = 0x90ee90;
pub const LightCyan = 0xe0ffff;
pub const LightRed = 0xffcccb;
pub const LightMagenta = 0xff80ff;
pub const LightBrown = 0xc4a484;
pub const White = 0xFFFFFF;

pub fn R(c: u32) u8 {
    return @truncate(u8, c >> 16);
}

pub fn G(c: u32) u8 {
    return @truncate(u8, c >> 8);
}

pub fn B(c: u32) u8 {
    return @truncate(u8, c);
}
