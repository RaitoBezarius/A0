const std = @import("std");
const graphics = @import("lib").graphics.Graphics;
const tty = @import("lib").graphics.Tty;
const Color = @import("lib").graphics.Color;
const uefi = @import("std").os.uefi;
const uefiConsole = @import("../uefi/console.zig");
const platform = @import("../arch/x86/platform.zig"); // TODO(w)
const serial = @import("../debug/serial.zig");

var graphicsOutputProtocol: ?*uefi.protocols.GraphicsOutputProtocol = undefined;

fn setupMode(index: u32) void {
    _ = graphicsOutputProtocol.?.setMode(index);

    const info = graphicsOutputProtocol.?.mode.info;
    var fb = graphics.Framebuffer{
        .width = info.horizontal_resolution,
        .height = info.vertical_resolution,
        .basePtr = @intToPtr([*]graphics.Pixel, graphicsOutputProtocol.?.mode.frame_buffer_base),
        .valid = true,
    };
    graphics.initialize(fb);

    // Put the cursor at the center.
    graphics.setCursorCoords(@divTrunc(@bitCast(i32, fb.width), 2), @divTrunc(@bitCast(i32, fb.height), 2));
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
    } else {
        @panic("Graphics output protocol is NOT supported, failing.\n");
    }
}

// TTY

pub fn serialPrint(comptime format: []const u8, args: anytype) void {
    tty.print(format, args);
    serial.printf(format, args);
}

pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    tty.colorPrint(Color.White, null, "\nKERNEL PANIC: " ++ format ++ "\n", args);
    serial.writeText("\n!!!!!!!!!!!!! KERNEL PANIC !!!!!!!!!!!!!!!\n");
    serial.printf(format ++ "\n", args);
    platform.hang();
}
