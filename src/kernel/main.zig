const std = @import("std");
const uefi = std.os.uefi;

const uefiAllocator = @import("uefi/allocator.zig");
const uefiMemory = @import("uefi/memory.zig");
const uefiConsole = @import("uefi/console.zig");
const uefiSystemInfo = @import("uefi/systeminfo.zig");

const graphics = @import("graphics/graphics.zig");
const Color = @import("graphics/color.zig");
const tty = @import("graphics/tty.zig");
const platform = @import("platform.zig");
const scheduler = @import("scheduler.zig");
const ipc = @import("ipc.zig");
const serial = @import("debug/serial.zig");
const bootscreen = @import("graphics/bootscreen.zig");

// Default panic handler for Zig.
pub const panic = serial.panic;

fn os_banner() void {
    const title = "A/0 - v0.0.1";
    tty.alignCenter(title.len);
    tty.colorPrint(Color.LightRed, null, "{s}\n\n", .{title});
    tty.colorPrint(Color.LightBlue, null, "Booting the microkernel:\n", .{});
}

fn user_fn() void {
    while (true) {}
}

const SegmentInfo = struct {
    start: u64,
    pagesLen: u64,
};

// Returns the address of the free segment that contains the most pages
fn doExitBootServices(bootServices: *uefi.tables.BootServices) SegmentInfo {
    // get the current memory map
    var memoryMap: [*]uefi.tables.MemoryDescriptor = undefined;
    var memoryMapSize: usize = 0;
    var memoryMapKey: usize = undefined;
    var descriptorSize: usize = undefined;
    var descriptorVersion: u32 = undefined;

    while (uefi.Status.BufferTooSmall == bootServices.getMemoryMap(&memoryMapSize, memoryMap, &memoryMapKey, &descriptorSize, &descriptorVersion)) {
        if (uefi.Status.Success != bootServices.allocatePool(uefi.tables.MemoryType.BootServicesData, memoryMapSize, @ptrCast(*[*]align(8) u8, &memoryMap))) {
            tty.panic("Could not access the memory map.", .{});
        }
    }

    serial.writeText("\n\n");

    const conventionalMemory = uefi.tables.MemoryType.ConventionalMemory;
    const bootServicesCode = uefi.tables.MemoryType.BootServicesCode;
    const bootServicesData = uefi.tables.MemoryType.BootServicesData;

    var mem: ?u64 = null;
    var maxPages: u64 = 0;

    var i: u64 = 0;
    var currStart: ?u64 = null;
    var currEnd: u64 = 0;
    while (i < memoryMapSize / descriptorSize) : (i += 1) {
        const desc = memoryMap[i];
        const end = desc.physical_start + desc.number_of_pages * 4096;
        if (desc.type != conventionalMemory and desc.type != bootServicesCode and desc.type != bootServicesData) {
            continue;
        }

        if (currStart) |start| {
            if (currEnd == desc.physical_start) {
                currEnd = end;
            } else {
                const pages = (currEnd - start) / 4096;
                serial.printf("{x:0>16}..{x:0>16} : {} (0x{x}) pages\n", .{ start, currEnd, pages, pages });
                currStart = desc.physical_start;
                currEnd = end;

                if (maxPages < pages) {
                    mem = currStart;
                    maxPages = pages;
                }
            }
        } else {
            currStart = desc.physical_start;
            currEnd = end;
        }
    }
    if (currStart) |start| {
        const pages = (currEnd - start) / 4096;
        serial.printf("{x:0>16}..{x:0>16} : {} ({x}) pages\n", .{ start, currEnd, pages, pages });

        if (maxPages < pages) {
            mem = currStart;
            maxPages = pages;
        }
    }

    serial.writeText("\n\n");

    if (bootServices.exitBootServices(uefi.handle, memoryMapKey) != uefi.Status.Success) {
        tty.panic("Failed to exit boot services.", .{});
    }

    if (mem) |addr| {
        return SegmentInfo{ .start = addr, .pagesLen = maxPages };
        //pmem.registerAvailableMem(addr);
    } else {
        tty.panic("Not enough memory.", .{});
    }
}

pub fn dumpState(comptime format: []const u8, args: anytype) void {
    tty.serialPrint("  >   " ++ format, args);
}

pub fn main() void {
    uefiMemory.initialize();
    uefiConsole.initialize();

    uefiConsole.puts("UEFI console initialized.\r\n");
    serial.initialize(serial.SERIAL_COM1, 2);
    uefiConsole.puts("User serial console initialized.\r\n");
    graphics.initialize();
    uefiConsole.puts("UEFI GOP initialized.\r\n");
    tty.initialize();
    tty.serialPrint("TTY initialized\n", .{});

    // UEFI-specific initialization
    const bootServices = uefi.system_table.boot_services.?;
    tty.serialPrint("Platform state:\n", .{});
    uefiSystemInfo.dumpAndAssertPlatformState(dumpState);
    tty.serialPrint("UEFI memory and debug console setup.\n", .{});

    scheduler.initialize(@frameAddress(), @frameSize(main), uefiAllocator.systemAllocator) catch |err| {
        tty.panic("Failed to initialize scheduler: {}", .{err});
    };
    bootscreen.bootVideo(uefiAllocator.systemAllocator) catch |err| {
        tty.panic("Failed to initialize boot video: {}", .{err});
    };

    tty.step("Platform preinitialization...", .{});
    platform.preinitialize();
    tty.stepOK();
    tty.serialPrint("Platform preinitialized, can now exit boot services.\n", .{});

    const longestSegment = doExitBootServices(bootServices);

    uefiConsole.disable(); // conOut is a boot service, so it's not available anymore.
    tty.serialPrint("Boot services exitted. UEFI console is now unavailable.\n", .{});

    graphics.selfTest();
    tty.serialPrint("Graphics subsystem self test completed.\n", .{});
    tty.selfTest();
    graphics.clear(Color.Black);

    os_banner();

    tty.step("Platform initialization", .{});
    var kernelAllocator = platform.initialize(longestSegment.start, longestSegment.pagesLen);
    tty.stepOK();

    ipc.initialize(kernelAllocator) catch |err| {
        serial.ppanic("Failed to initialize IPC: {}", .{err});
    };

    // runtimeServices.set_virtual_address_map();

    tty.colorPrint(Color.LightBlue, null, "\nLoading the servers (driverspace):\n", .{});

    // The OS is now running.
    // liftoff to a user init task, pid 1.
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
