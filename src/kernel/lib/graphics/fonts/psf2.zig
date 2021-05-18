const fmt = @import("std").fmt;
const uefiConsole = @import("../uefi/console.zig");
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
pub const defaultFont = @ptrCast([*]const u8, rawFontBuffer);

pub fn asFont(buffer: [*]const u8) *const Font {
    return @ptrCast(*const Font, buffer);
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

pub fn debugGlyph(font: *const Font, glyph_index: u32) void {
    if (glyph_index < 0 or glyph_index >= font.numGlyphs) {
        return serial.writeText("out of range glyph\r\n");
    }
    const start = glyph_index * font.bytesPerGlyph;
    const glyph = font.data()[start .. start + 16];
    serial.printf("{} out of {}, offset {}, glyp at {*}\n", .{ glyph_index, font.numGlyphs, font.headerSize, font.data() + start });
    for (glyph) |l| {
        serial.printf("{b:0>8}\n", .{l});
    }
}

pub fn renderChar(font: *const Font, dest: [*]u32, char: u8, cx: i32, cy: i32, fg: u32, bg: u32, scanLine: u32) void {
    const bytesPerLine: u32 = (font.width + 7) / 8;
    var glyph = font.data() + (if (char > 0 and char < font.numGlyphs) char else 0) * font.bytesPerGlyph;
    var linePtr = dest + @bitCast(u32, (cy * @bitCast(i32, scanLine)) + cx);

    var y: u32 = 0;
    while (y < font.height) : (y += 1) {
        var mask: u32 = @as(u32, 1) << @truncate(u5, (font.width - 1));
        var lineByte: u32 = 0;
        while (lineByte < bytesPerLine) : (lineByte += 1) {
            const castedGlyph = @as(u32, glyph[0]) << @truncate(u5, (bytesPerLine - lineByte - 1));
            var byteRowPtr = linePtr + lineByte * 8;
            var x: u32 = 0;
            while (x < font.width) : (x += 1) {
                var target = byteRowPtr + x;
                target.* = (if (castedGlyph & mask > 0) fg else bg);
                mask >>= 1;
            }
            glyph += 1;
        }
        linePtr += scanLine;
    }
}
