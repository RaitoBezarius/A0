const PSF_FONT_MAGIC: u32 = 0x864ab572;

const PSFHeader = struct {
    magic: u32, version: u32, // Zero
    headerSize: u32, // Offset of bitmaps in file, 32
    flags: u32, // 0 if no unicode table
    numGlyphs: u32, // Number of glyphs
    bytesPerGlyph: u32, // Size of each glyph
    height: u32, // Height in pixels
    width: u32 // Width in pixels
};

const Font = struct {
    header: PSFHeader, data: [*]u8
};

const defaultFontBuffer = @embedFile("Lat2-Terminus16.psfu");
pub const defaultFont: *const Font = @ptrCast(*const Font, defaultFontBuffer);

pub fn putchar(font: *const Font, dest: *[*]u8, c: u8, cx: i32, cy: i32, fg: u32, bg: u32, scanLine: u32) void {
    const bytesPerLine = (font.header.width + 7) / 8;

    var glyph = font.data + (if (c > 0 and c < font.header.numGlyphs) c else 0) * font.header.bytesPerGlyph;

    var offsets = (cy * @bitCast(i32, font.header.height) * @bitCast(i32, scanLine)) + (cx * @bitCast(i32, (font.header.width + 1)) * 4);

    var x: u32 = 0;
    var y: u32 = 0;
    var line: i32 = undefined;
    var mask: u32 = undefined;

    while (y < font.header.height) : (y += 1) {
        line = offsets;

        mask = @as(u32, 1) << @truncate(u5, (font.header.width - 1));

        while (x < font.header.width) : (x += 1) {
            var target: *u32 = @intToPtr(*u32, @ptrToInt(dest) + @bitCast(u32, line));
            const castedGlyph = @ptrToInt(@ptrCast(*u32, @alignCast(4, glyph)));
            target.* = if ((castedGlyph & mask) - 1 >= (mask - 1)) fg else bg;
            mask >>= 1;
            line += 4;
        }

        glyph += bytesPerLine;
        offsets += @bitCast(i32, scanLine);
    }
}
