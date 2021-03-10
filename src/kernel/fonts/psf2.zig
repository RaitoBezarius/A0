const fmt = @import("std").fmt;
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

fn hexdump(buffer: [*]const u8, length: u32) [512]u8 {
    var i: u64 = 0;
    var j: u32 = 0;
    var outBuffer: [512]u8 = undefined;

    while (j < length and i < 512) : (j += 1) {
        _ = fmt.bufPrint(outBuffer[i..], "{x}", .{0xFF & buffer[j]}) catch unreachable;
        i += fmt.count("{x}", .{0xFF & buffer[i]});
    }

    return outBuffer;
}

pub fn debugGlyph(buffer: []u8, font: *const Font, glyph_index: u32) []const u8 {
    if (glyph_index < 0 or glyph_index >= font.numGlyphs) {
        return fmt.bufPrint(buffer, "out of range glyph\r\n", .{}) catch unreachable;
    }

    const start = glyph_index * font.bytesPerGlyph;
    const glyph = font.data()[start .. start + 16];
    return fmt.bufPrint(buffer, "bytes: {x}\r\n", .{glyph[0]}) catch unreachable;
}

pub fn renderChar(font: *const Font, dest: *[*]u8, c: u8, cx: i32, cy: i32, fg: u32, bg: u32, scanLine: u32) void {
    const bytesPerLine = (font.width + 7) / 8;

    var glyph = font.data() + (if (c > 0 and c < font.numGlyphs) c else 0) * font.bytesPerGlyph;

    var offsets = (cy * @bitCast(i32, font.height) * @bitCast(i32, scanLine)) + (cx * @bitCast(i32, (font.width + 1)) * 4);

    var x: u32 = 0;
    var y: u32 = 0;
    var line: usize = undefined;
    var mask: u32 = undefined;

    while (y < font.height) : (y += 1) {
        line = @as(usize, @bitCast(u32, offsets));

        mask = @as(u32, 1) << @truncate(u5, (font.width - 1));

        while (x < font.width) : (x += 1) {
            var target: *u32 = @ptrCast(*u32, @alignCast(4, dest.* + line));
            const castedGlyph = @ptrToInt(@ptrCast(*const u32, @alignCast(4, glyph)));
            target.* = if ((castedGlyph & mask) - 1 >= (mask - 1)) fg else bg;
            mask >>= 1;
            line += 4;
        }

        glyph += bytesPerLine;
        offsets += @bitCast(i32, scanLine);
    }
}
