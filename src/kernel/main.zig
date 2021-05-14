const std = @import("std");
const uefi = std.os.uefi;

const uefiAllocator = @import("uefi/allocator.zig");
const uefiMemory = @import("uefi/memory.zig");
const uefiConsole = @import("uefi/console.zig");
const uefiSystemInfo = @import("uefi/systeminfo.zig");

const graphics = @import("graphics.zig");
const Color = @import("color.zig");
const tty = @import("tty.zig");
const platform = @import("platform.zig");
const scheduler = @import("scheduler.zig");
const serial = @import("debug/serial.zig");

// Default panic handler for Zig.
pub const panic = serial.panic;

//fn os_banner() void {
//    const title = "A/0 - v0.0.1";
//    tty.alignCenter(title.len);
//    tty.colorPrint(Color.LightRed, title ++ "\n\n");
//
//    tty.colorPrint(Color.LightBlue, "Booting the microkernel:\n");
//}

fn user_fn() void {
    while (true) {}
}

pub fn main() void {
    // FIXME(Ryan): complete the Graphics & TTY kernel impl to enable scrolling.
    // Then reuse it for everything else.
    uefiMemory.initialize();
    uefiConsole.initialize();

    uefiConsole.puts("UEFI console initialized.\r\n");
    serial.initialize(serial.SERIAL_COM1, 2);
    uefiConsole.puts("User serial console initialized.\r\n");
    graphics.initialize();
    uefiConsole.puts("UEFI GOP initialized.\r\n");

    // UEFI-specific initialization
    const bootServices = uefi.system_table.boot_services.?;
    uefiSystemInfo.dumpAndAssertPlatformState();
    uefiConsole.puts("UEFI memory and debug console setup.\r\n");

    scheduler.initialize(@frameAddress(), @frameSize(main), uefiAllocator.systemAllocator) catch |err| {
        serial.ppanic("Failed to initialize scheduler: {}", .{err});
    };
    // scheduler.self_test_init(uefiAllocator.systemAllocator) catch |err| {
    //     serial.ppanic("Failed to initialize scheduler tests: {}", .{err});
    // };
    tty.initialize(uefiAllocator.systemAllocator);

    tty.serialPrint("Platform preinitialization...\n", .{});
    platform.preinitialize(uefiAllocator.systemAllocator);
    tty.serialPrint("Platform preinitialized, can now exit boot services.\n", .{});

    uefiMemory.memoryMap.refresh(); // Refresh the memory map before the exit.
    var retCode = bootServices.exitBootServices(uefi.handle, uefiMemory.memoryMap.key);
    if (retCode != uefi.Status.Success) {
        return;
    }
    uefiConsole.disable(); // conOut is a boot service, so it's not available anymore.
    tty.serialPrint("Boot services exitted. UEFI console is now unavailable.\n", .{});

    tty.serialPrint("Platform initialization...\n", .{});
    platform.initialize();
    tty.serialPrint("Platform initialized.\n", .{});

    // scheduler.selfTest();

    // TODO: graphics tests work well only when scheduler is disabled, or at low frequency. Seems a graphic buffer issue (?). Currently, freq = 19.
    // graphics.selfTest();
    // tty.serialPrint("Graphics subsystem self test completed.\n", .{});
    // tty.selfTest();

    // runtimeServices.set_virtual_address_map();

    //mem.initialize(MEMORY_OFFSET);
    //timer.initialize(100);
    //scheduler.initialize();

    //tty.colorPrint(Color.LightBlue, "\nLoading the servers (driverspace):\n");

    // The OS is now running.
    //var user_stack: [1024]u64 = undefined;
    //platform.liftoff(&user_fn, &user_stack[1023]); // Go to userspace.
    platform.hlt();
}

// This code solves the queens problem. Used to test if the code execution is correct

const N_QUEENS: i64 = 9;
var echiquier: [N_QUEENS][N_QUEENS]bool = undefined;

fn cellOk(x: usize, y: usize) bool {
    var i: usize = 0;
    while (i < N_QUEENS) : (i += 1) {
        var j: usize = 0;
        while (j < N_QUEENS) : (j += 1) {
            if (echiquier[i][j]) {
                if (i == x or j == y or x + j == y + i or x + y == i + j) {
                    return false;
                }
            }
        }
    }
    return true;
}

fn solve(n: i64, i_deb: usize, j_deb: usize) i64 {
    if (n == N_QUEENS) {
        return 1;
    }
    var r: i64 = 0;
    var i: usize = i_deb;
    var j: usize = j_deb;
    while (i < N_QUEENS) : (i += 1) {
        while (j < N_QUEENS) : (j += 1) {
            if (cellOk(i, j)) {
                echiquier[i][j] = true;
                r += solve(n + 1, i, j);
                echiquier[i][j] = false;
            }
        }
        j = 0;
    }
    return r;
}

fn doSomeTest() void {
    var i: usize = 0;
    while (i < N_QUEENS) : (i += 1) {
        var j: usize = 0;
        while (j < N_QUEENS) : (j += 1) {
            echiquier[i][j] = false;
        }
    }
    tty.serialPrint("Solutions: {}\n\n\n\n\n\n\n\n\n\n\n\n\n\n", .{solve(0, 0, 0)});
    tty.serialPrint("========== END", .{});
}
