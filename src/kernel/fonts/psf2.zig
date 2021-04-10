const fmt = @import("std").fmt;
const serial = @import("../debug/serial.zig");
const PSF_FONT_MAGIC: u32 = 0x864ab572;

const Font = packed struct {
    magic: u32,
    version: u32, // Zero
    headerSize: u32, // Offset of bitmaps in file, 32
    flags: u32, // 0 if no unicode table
    numGlyphs: u32, // Number of glyphs
    bytesPerGlyph: u32, // Size of each glyph
    height: u32, // Height in pixels
    width: u32, // Width in pixels
    fn data(self: *const Font) [*]const u8 {
        return @ptrCast([*]const u8, self) + self.headerSize;
    }
};

const rawFontBuffer = @embedFile("Lat2-Terminus16.psfu");
const defaultFontBuffer = @ptrCast(*const [*]u8, rawFontBuffer);
pub fn fromBuffer(buffer: *const [*]u8) ?*const Font {
    const font: *align(8) const Font = @ptrCast(*align(8) const Font, buffer);
    if (font.magic != PSF_FONT_MAGIC) {
        return null;
    } else {
        return font;
    }
}
pub const defaultFont: *const Font = fromBuffer(defaultFontBuffer).?;

pub fn selfTest() void {
    const glyphIndex = defaultFont.headerSize + @as(u8, 'a') * defaultFont.bytesPerGlyph;
    const glyphIndexEnd = glyphIndex + defaultFont.bytesPerGlyph;
    const buffer = defaultFontBuffer.*;
    const slice = buffer[glyphIndex..glyphIndexEnd];
    serial.writeText("Glyph for a: {x}\n", .{@bitCast(u128, slice.*)});
}

fn hexdump(buffer: []const u8, length: u32) [512]u8 {
    var i: u64 = 0;
    var j: u32 = 0;
    var outBuffer: [512]u8 = undefined;

    while (j < length and i < 512) : (j += 1) {
        _ = fmt.bufPrint(outBuffer[i..], "{}", .{0xFF & buffer[j]}) catch unreachable;
        i += fmt.count("{}", .{0xFF & buffer[i]});
    }

    return outBuffer;
}

pub fn debugGlyph(buffer: []u8, font: *const Font, glyph_index: u32) []const u8 {
    if (glyph_index < 0 or glyph_index >= font.numGlyphs) {
        return fmt.bufPrint(buffer, "out of range glyph\r\n", .{}) catch unreachable;
    }

    const start = glyph_index * font.bytesPerGlyph;
    const glyph = font.data()[start .. start + 16];
    return fmt.bufPrint(buffer, "bytes: {x}\r\n", .{glyph}) catch unreachable;
}

pub fn renderChar(font: *const Font, dest: [*]u8, c: u8, cx: u32, cy: u32, fg: u32, bg: u32, scanLine: u32) void {
    const bytesPerLine = (font.width + 7) / 8;
    var glyph: [16]u8 = (@bitCast([16]u8, @as(u128, 0xb9a5b9817e000000))); //font.data() + (if (c > 0 and c < font.numGlyphs) c else 0) * font.bytesPerGlyph;

    var y: u32 = 0;
    var buf: [4096]u8 = undefined;

    while (y < font.height) : (y += 1) {
        var x: u4 = 0;

        while (x < font.width) : (x += 1) {
            const index = 4 * ((cy * font.height + y) * scanLine + (cx * font.width + x));
            dest[index] = if ((glyph[y] & (1 >> @truncate(u3, x))) & 1 != 0) @truncate(u8, fg) else @truncate(u8, bg);
            dest[index + 1] = dest[index];
            dest[index + 2] = dest[index];
        }
    }
}
