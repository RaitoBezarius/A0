const uefi = @import("std").os.uefi;
// const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;
const platform = @import("arch/x86/platform.zig");
const fmt = @import("std").fmt;
const psf2 = @import("fonts/psf2.zig");
const ColorMod = @import("color.zig");
const Color = ColorMod.Color;
const uefiConsole = @import("uefi/console.zig");

var graphicsOutputProtocol: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

const Pixel = packed struct {
    blue: u8,
    green: u8,
    red: u8,
    pad: u8 = undefined,
};

fn pixelFromColor(c: Color) Pixel {
    return Pixel{
        .blue = ColorMod.B(c),
        .green = ColorMod.G(c),
        .red = ColorMod.R(c),
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

const CursorState = struct { x: i32, y: i32 };

const ScreenState = struct { cursor: CursorState };

var state = ScreenState{
    .cursor = CursorState{
        .x = 0,
        .y = 0,
    },
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

const MOST_APPROPRIATE_W = 1920;
const MOST_APPROPRIATE_H = 1440;
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

pub fn setPixel(w: u32, h: u32, rgb: u32) void {
    if (!fb.valid) @panic("Invalid framebuffer!");
    fb.basePtr[4 * (w + h * fb.pixelsPerScanLine)] = pixelFromColor(@intToEnum(Color, rgb | 0xff000000));
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

pub fn clear(color: Color) void {
    drawRect(fb.width, fb.height, color);
    // TODO: Reset cursor.
}
pub fn setTextColor(color: Color) void {
    // Store current text color
}
pub fn getTextColor() Color {
    // Return current text color
}

pub fn drawRect(w: u32, h: u32, c: Color) void {
    if (!fb.valid) @panic("Invalid framebuffer!\n");
    var i: u32 = 0;
    var where: [*]u8 = @ptrCast([*]u8, fb.basePtr);

    while (i < w) : (i += 1) {
        var j: u32 = 0;
        while (j <= h) : (j += 1) {
            where[4 * j] = ColorMod.R(c);
            where[4 * j + 1] = ColorMod.G(c);
            where[4 * j + 2] = ColorMod.B(c);
        }
        where += 3200;
    }
}

pub fn drawChar(c: u8, fg: Color, bg: Color) void {
    if (!fb.valid) @panic("Invalid framebuffer!");
    // Draw a character at the current cursor.
    var buf: [4096]u8 = undefined;
    uefiConsole.printf(buf[0..], "write {} @ cursor: {}\r\n", .{ c, state.cursor });
    uefiConsole.puts(psf2.debugGlyph(buf[0..], psf2.defaultFont, @as(u32, c)));
    psf2.renderChar(psf2.defaultFont, @ptrCast([*]u8, fb.basePtr), c, state.cursor.x, state.cursor.y, @enumToInt(fg), @enumToInt(bg), fb.pixelsPerScanLine);

    state.cursor.x += 1;
    if (state.cursor.x >= fb.width) {
        state.cursor.y += 1;
        state.cursor.x = 0;
    }
}
pub fn drawText(text: []const u8) void {
    // Iterate over all char and draw each char.
}
pub fn alignLeft(offset: usize) void {
    // Move cursor left of offset chars.
}

pub fn selfTest() void {
    clear(Color.Black);
    drawChar('a', Color.White, Color.Black);
    //clear(Color.White);
}
