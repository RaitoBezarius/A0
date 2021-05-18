const fmt = @import("std").fmt;
const psf2 = @import("fonts/psf2.zig");
const Color = @import("color.zig");

pub const Pixel = packed struct {
    blue: u8,
    green: u8,
    red: u8,
    pad: u8 = undefined,
};

pub const Dimensions = packed struct {
    height: u32,
    width: u32,
};

pub const Position = packed struct {
    x: i32,
    y: i32,
};

pub const TextColor = packed struct {
    fg: u32,
    bg: u32,
};

const ScreenState = struct {
    cursor: Position,
    textColor: TextColor,
    font: [*]const u8,
};

pub const Framebuffer = struct { width: u32, height: u32, basePtr: [*]Pixel, valid: bool };

var fb = Framebuffer{
    .width = 0,
    .height = 0,
    .basePtr = undefined,
    .valid = false,
};
pub var totalScroll: u64 = 0;

pub fn initialize(frameBuffer: Framebuffer) void {
    fb = frameBuffer;
    clear(Color.Black);
}

pub fn pixelFromColor(c: u32) Pixel {
    return Pixel{
        .blue = Color.B(c),
        .green = Color.G(c),
        .red = Color.R(c),
    };
}

var state = ScreenState{
    .cursor = Position{
        .x = 0,
        .y = 0,
    },
    .textColor = TextColor{
        .fg = 0xffffff,
        .bg = 0,
    },
    .font = psf2.defaultFont,
};

pub fn clear(color: u32) void {
    drawRect(0, 0, fb.width, fb.height, color);

    // Put the cursor at the center.
    state.cursor.x = @divTrunc(@bitCast(i32, fb.width), 2);
    state.cursor.y = @divTrunc(@bitCast(i32, fb.height), 2);
}
pub fn setTextColor(fg: ?u32, bg: ?u32) void {
    if (fg) |fgColor| {
        state.textColor.fg = fgColor;
    }
    if (bg) |bgColor| {
        state.textColor.bg = bgColor;
    }
}
pub fn getTextColor() TextColor {
    return state.textColor;
}
pub fn getDimensions() Dimensions {
    return Dimensions{
        .height = fb.height,
        .width = fb.width,
    };
}

pub fn setPixel(x: u32, y: u32, rgb: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!");
    fb.basePtr[(x + y * fb.width)] = pixelFromColor(rgb);
}

pub fn drawRect(x: u32, y: u32, w: u32, h: u32, rgb: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    const pixelColor = pixelFromColor(rgb);
    const lastLine = y + h;
    const lastCol = x + w;
    var linePtr = fb.basePtr + (fb.width * y);
    var iLine = y;

    while (iLine < lastLine) : (iLine += 1) {
        var iCol: u32 = x;
        while (iCol < lastCol) : (iCol += 1) {
            linePtr[iCol] = pixelColor;
        }
        linePtr += fb.width;
    }
}

pub fn fromRawPixels(x: u32, y: u32, w: u32, h: u32, raw: [*]const Pixel) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    const lastLine = y + h;
    const lastCol = x + w;
    var linePtr = fb.basePtr + (fb.width * y);
    var rawPtr = raw;
    var iLine = y;

    while (iLine < lastLine) : (iLine += 1) {
        var iCol: u32 = x;
        while (iCol < lastCol) : (iCol += 1) {
            linePtr[iCol] = rawPtr[0];
            rawPtr += 1;
        }
        linePtr += fb.width;
    }
}

pub fn fromRawPixelsScale(x: u32, y: u32, w: u32, h: u32, raw: [*]const Pixel, ratio: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    const lastLine = y + h;
    const lastCol = x + w * ratio;
    var linePtr = fb.basePtr + (fb.width * y);
    var iLine = y;

    while (iLine < lastLine) : (iLine += 1) {
        var repeat_h: u32 = 0;
        while (repeat_h < ratio) : (repeat_h += 1) {
            var rawLinePtr = raw + iLine * w;
            var iCol: u32 = x;
            while (iCol < lastCol) : (iCol += ratio) {
                var repeat_w: u32 = 0;
                while (repeat_w < ratio) : (repeat_w += 1) {
                    linePtr[iCol + repeat_w] = rawLinePtr[0];
                }
                rawLinePtr += 1;
            }
            linePtr += fb.width;
        }
    }
}

pub fn drawChar(char: u8, fg: u32, bg: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!");
    // Draw a character at the current cursor.

    var font = psf2.asFont(state.font);
    psf2.renderChar(font, @ptrCast([*]u32, @alignCast(32, fb.basePtr)), char, state.cursor.x, state.cursor.y, fg, bg, fb.width);

    state.cursor.x += @bitCast(i32, font.width);
    if (state.cursor.x > fb.width - font.width) {
        state.cursor.y += @bitCast(i32, font.height);
        state.cursor.x = 0;
    }
}
pub fn drawText(text: []const u8) void {
    // Iterate over all char and draw each char.
    for (text) |char| {
        drawChar(char, state.textColor.fg, state.textColor.bg);
    }
}
pub fn textAlignLeft(offset: usize) void {
    const font = psf2.asFont(state.font);
    // Move cursor left of offset chars.
    state.cursor.x = @bitCast(i32, @truncate(u32, offset * font.width));
}
pub fn moveTextCursor(vOffset: i32, hOffset: i32) void {
    const font = psf2.asFont(state.font);
    // Move cursor left, right, bottom, top
    state.cursor.x += hOffset * @bitCast(i32, font.width);
    state.cursor.y += vOffset * @bitCast(i32, font.height);
}
pub fn setCursorCoords(x: i32, y: i32) void {
    state.cursor.x = x;
    state.cursor.y = y;
}
pub fn getCursorPos() Position {
    return state.cursor;
}

pub fn scroll(px: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    totalScroll += @as(u64, px);
    var lineSize = fb.width;
    var prevLinePtr = fb.basePtr;
    var linePtr = fb.basePtr + px * lineSize;
    var iLine: u32 = px;

    while (iLine < fb.height) : (iLine += 1) {
        var iCol: u32 = 0;
        while (iCol < lineSize) : (iCol += 1) {
            prevLinePtr[iCol] = linePtr[iCol];
        }
        linePtr += lineSize;
        prevLinePtr += lineSize;
    }
    // And fill remaining lines
    iLine = fb.height - px;
    var pixelColor = pixelFromColor(state.textColor.bg);
    while (iLine < fb.height) : (iLine += 1) {
        var iCol: u32 = 0;
        while (iCol < lineSize) : (iCol += 1) {
            prevLinePtr[iCol] = pixelColor;
        }
        prevLinePtr += lineSize;
    }
}

pub fn selfTest() void {
    clear(Color.Black);
    clear(Color.Green);
    drawRect(10, 30, 780, 540, Color.Red);
    setPixel(0, 0, Color.Cyan);
    setTextColor(Color.Red, Color.Blue);
    drawText("Hello there!");
}
