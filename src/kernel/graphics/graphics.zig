const uefi = @import("std").os.uefi;
// const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;
const platform = @import("../arch/x86/platform.zig");
const fmt = @import("std").fmt;
const psf2 = @import("../fonts/psf2.zig");
const Color = @import("color.zig");
const uefiConsole = @import("../uefi/console.zig");

var graphicsOutputProtocol: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

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

fn pixelFromColor(c: u32) Pixel {
    return Pixel{
        .blue = Color.B(c),
        .green = Color.G(c),
        .red = Color.R(c),
    };
}

const Framebuffer = struct { width: u32, height: u32, pixelsPerScanLine: u32, basePtr: [*]Pixel, valid: bool };

var fb: Framebuffer = Framebuffer{
    .width = 0,
    .height = 0,
    .pixelsPerScanLine = 0,
    .basePtr = undefined,
    .valid = false,
};

const ScreenState = struct {
    cursor: Position,
    textColor: TextColor,
    font: [*]const u8,
};

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

fn setupMode(index: u32) void {
    _ = graphicsOutputProtocol.?.setMode(index);

    const info = graphicsOutputProtocol.?.mode.info;
    fb.width = info.horizontal_resolution;
    fb.height = info.vertical_resolution;
    fb.pixelsPerScanLine = info.pixels_per_scan_line;
    fb.basePtr = @intToPtr([*]Pixel, graphicsOutputProtocol.?.mode.frame_buffer_base);
    fb.valid = true;

    // Put the cursor at the center.
    state.cursor.x = @divTrunc(@bitCast(i32, fb.width), 2);
    state.cursor.y = @divTrunc(@bitCast(i32, fb.height), 2);
}

const MOST_APPROPRIATE_W = 960;
const MOST_APPROPRIATE_H = 720;
fn selectBestMode() void {
    var bestMode = .{ graphicsOutputProtocol.?.mode.mode, graphicsOutputProtocol.?.mode.info };
    var i: u8 = 0;
    while (i < graphicsOutputProtocol.?.mode.max_mode) : (i += 1) {
        var info: *uefi.protocols.GraphicsOutputModeInformation = undefined;
        var info_size: usize = undefined;
        _ = graphicsOutputProtocol.?.queryMode(i, &info_size, &info);

        if (info.horizontal_resolution > MOST_APPROPRIATE_W and
            info.vertical_resolution > MOST_APPROPRIATE_H)
        {
            continue;
        }

        if (info.horizontal_resolution == MOST_APPROPRIATE_W and
            info.vertical_resolution == MOST_APPROPRIATE_H)
        {
            bestMode.@"0" = i;
            bestMode.@"1" = info;
            break;
        }

        if (info.vertical_resolution > bestMode.@"1".vertical_resolution) {
            bestMode.@"0" = i;
            bestMode.@"1" = info;
        }
    }

    setupMode(bestMode.@"0");
}

pub fn initialize() void {
    const boot_services = uefi.system_table.boot_services.?;
    var buf: [100]u8 = undefined;

    if (boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphicsOutputProtocol)) == uefi.Status.Success) {
        uefiConsole.puts("[LOW-LEVEL DEBUG] Graphics output protocol is supported!\r\n");

        var i: u8 = 0;
        while (i < graphicsOutputProtocol.?.mode.max_mode) : (i += 1) {
            var info: *uefi.protocols.GraphicsOutputModeInformation = undefined;
            var info_size: usize = undefined;
            _ = graphicsOutputProtocol.?.queryMode(i, &info_size, &info);

            uefiConsole.printf(buf[0..], "    mode {} = {}x{}\r\n", .{
                i,                        info.horizontal_resolution,
                info.vertical_resolution,
            });
        }

        uefiConsole.printf(buf[0..], "    current mode = {}\r\n", .{graphicsOutputProtocol.?.mode.mode});

        // Move to larger mode.
        selectBestMode();
        // uefiConsole.disable();

        const curMode = graphicsOutputProtocol.?.mode.mode;
        var info: *uefi.protocols.GraphicsOutputModeInformation = undefined;
        var info_size: usize = undefined;
        _ = graphicsOutputProtocol.?.queryMode(curMode, &info_size, &info);
        uefiConsole.printf(buf[0..], "    current mode = {}x{}x{}\r\n", .{ info.horizontal_resolution, info.vertical_resolution, info.pixels_per_scan_line });

        clear(Color.Black);
        uefiConsole.puts("Screen cleared.\r\n");
    } else {
        @panic("Graphics output protocol is NOT supported, failing.\n");
    }
}

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
    fb.basePtr[(x + y * fb.pixelsPerScanLine)] = pixelFromColor(rgb);
}

pub fn drawRect(x: u32, y: u32, w: u32, h: u32, rgb: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    const pixelColor = pixelFromColor(rgb);
    const lastLine = y + h;
    const lastCol = x + w;
    var linePtr = fb.basePtr + (fb.pixelsPerScanLine * y);
    var iLine = y;

    while (iLine < lastLine) : (iLine += 1) {
        var iCol: u32 = x;
        while (iCol < lastCol) : (iCol += 1) {
            linePtr[iCol] = pixelColor;
        }
        linePtr += fb.pixelsPerScanLine;
    }
}

pub fn fromRawPixels(x: u32, y: u32, w: u32, h: u32, raw: [*]const Pixel) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    const lastLine = y + h;
    const lastCol = x + w;
    var linePtr = fb.basePtr + (fb.pixelsPerScanLine * y);
    var rawPtr = raw;
    var iLine = y;

    while (iLine < lastLine) : (iLine += 1) {
        var iCol: u32 = x;
        while (iCol < lastCol) : (iCol += 1) {
            linePtr[iCol] = rawPtr[0];
            rawPtr += 1;
        }
        linePtr += fb.pixelsPerScanLine;
    }
}

pub fn drawChar(char: u8, fg: u32, bg: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!");
    // Draw a character at the current cursor.

    var font = psf2.asFont(state.font);
    psf2.renderChar(font, @ptrCast([*]u32, @alignCast(32, fb.basePtr)), char, state.cursor.x, state.cursor.y, fg, bg, fb.pixelsPerScanLine);

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
pub fn alignLeft(offset: usize) void {
    var font = psf2.asFont(state.font);
    // Move cursor left of offset chars.
    state.cursor.x = @bitCast(i32, @truncate(u32, offset * font.width));
}
pub fn moveCursor(vOffset: i32, hOffset: i32) void {
    var font = psf2.asFont(state.font);
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
    var lineSize = fb.pixelsPerScanLine;
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

const img = [_]Pixel{ pixelFromColor(Color.Magenta), pixelFromColor(Color.Magenta), pixelFromColor(Color.Magenta), pixelFromColor(Color.Red), pixelFromColor(Color.Green), pixelFromColor(Color.Red), pixelFromColor(Color.Blue), pixelFromColor(Color.Blue), pixelFromColor(Color.Blue) };

pub fn selfTest() void {
    clear(Color.Black);
    clear(Color.Green);
    drawRect(10, 30, 780, 540, Color.Red);
    setPixel(0, 0, Color.Cyan);
    setTextColor(Color.Red, Color.Blue);
    drawText("Hello there!");

    fromRawPixels(100, 100, 3, 3, &img);
}
