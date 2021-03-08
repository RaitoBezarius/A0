const uefi = @import("std").os.uefi;
// const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;
const platform = @import("arch/x86/platform.zig");
const fmt = @import("std").fmt;
const Color = @import("color.zig").Color;

var conOut: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var graphicsOutputProtocol: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

const Framebuffer = struct {
    width: u32, height: u32, pixelsPerScanLine: u32, basePtr: [*]u32, valid: bool
};

var fb: Framebuffer = Framebuffer{
    .width = 0,
    .height = 0,
    .pixelsPerScanLine = 0,
    .basePtr = undefined,
    .valid = false,
};

const ScreenState = struct {
    background: Color, foreground: Color
};

fn puts(msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2]u16{ c, 0 };
        _ = conOut.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

fn printf(buf: []u8, comptime format: []const u8, args: anytype) void {
    puts(fmt.bufPrint(buf, format, args) catch unreachable);
}

fn setupMode(index: u32) void {
    _ = graphicsOutputProtocol.?.setMode(index);

    const info = graphicsOutputProtocol.?.mode.info;
    fb.width = info.horizontal_resolution;
    fb.height = info.vertical_resolution;
    fb.pixelsPerScanLine = info.pixels_per_scan_line;
    fb.basePtr = @intToPtr([*]u32, @as(usize, graphicsOutputProtocol.?.mode.frame_buffer_base));
    fb.valid = true;
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

fn getFramebufferAddr(w: u32, h: u32) u32 {
    return fb.basePtr + 4 * w + 4 * h * fb.pixelsPerScanLine;
}

fn setPixel(w: u32, h: u32, rgb: u32) void {
    var targetAddr = getFramebufferAddr(w, h);
    *targetAddr = rgb | 0xff000000;
}

pub fn initialize() void {
    conOut = uefi.system_table.con_out.?;

    const boot_services = uefi.system_table.boot_services.?;
    var buf: [100]u8 = undefined;

    if (boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphicsOutputProtocol)) == uefi.Status.Success) {
        puts("[LOW-LEVEL DEBUG] Graphics output protocol is supported!\r\n");

        var i: u8 = 0;
        while (i < graphicsOutputProtocol.?.mode.max_mode) : (i += 1) {
            var info: *uefi.protocols.GraphicsOutputModeInformation = undefined;
            var info_size: usize = undefined;
            _ = graphicsOutputProtocol.?.queryMode(i, &info_size, &info);

            printf(buf[0..], "    mode {} = {}x{}\r\n", .{
                i,                        info.horizontal_resolution,
                info.vertical_resolution,
            });
        }

        printf(buf[0..], "    current mode = {}\r\n", .{graphicsOutputProtocol.?.mode.mode});

        // Move to larger mode.
        selectBestMode();
        puts("Graphics re-initialized.");

        const curMode = graphicsOutputProtocol.?.mode.mode;
        var info: *uefi.protocols.GraphicsOutputModeInformation = undefined;
        var info_size: usize = undefined;
        _ = graphicsOutputProtocol.?.queryMode(curMode, &info_size, &info);
        printf(buf[0..], "    current mode = {}x{}\r\n", .{ info.horizontal_resolution, info.vertical_resolution });

        clear(Color.Black);
    } else {
        panic("Graphics output protocol is NOT supported, failing.\r\n");
    }
}

pub fn panic(msg: []const u8) void {
    puts("KERNEL PANIC: ");
    puts(msg);
    puts("\r\n");
    platform.hang();
}

pub fn clear(color: Color) void {
    // Iterate over the screen and setPixel(x,y,color)
    // Reset cursor.
}
pub fn setTextColor(color: Color) void {
    // Store current text color
}
pub fn getTextColor() Color {
    // Return current text color
}
pub fn drawChar(c: u8) void {
    // Draw a character at the current cursor.
}
pub fn drawText(text: []const u8) void {
    // Iterate over all char and draw each char.
}
pub fn alignLeft(offset: usize) void {
    // Move cursor left of offset chars.
}
