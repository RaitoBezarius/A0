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

// Returns the address of a segment that contains at lean 64 free pages
fn do_exit_boot_services(boot_services : *uefi.tables.BootServices) u64 {
    // get the current memory map
    var memory_map: [*]uefi.tables.MemoryDescriptor = undefined;
    var memory_map_size: usize = 0;
    var memory_map_key: usize = undefined;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;
    
    while (uefi.Status.BufferTooSmall == boot_services.getMemoryMap(
            &memory_map_size, memory_map, &memory_map_key, &descriptor_size, &descriptor_version)
    ) {
        if (uefi.Status.Success != boot_services.allocatePool(
                uefi.tables.MemoryType.BootServicesData, memory_map_size, @ptrCast(*[*]align(8) u8, &memory_map)
        )) { panic("Could not access the memory map.", null); }
    }

    var i : usize = 0;
    var mem : ?u64 = null;
    while (i < memory_map_size / descriptor_size) : (i += 1) {
        if (memory_map[i].type == uefi.tables.MemoryType.ConventionalMemory) {
            if (memory_map[i].number_of_pages > 64) {
                mem = memory_map[i].physical_start;
            }
        }
    }
    
    serial.writeText("\n\n");

    const conventional_memory = uefi.tables.MemoryType.ConventionalMemory;
    const boot_services_code = uefi.tables.MemoryType.BootServicesCode;
    const boot_services_data = uefi.tables.MemoryType.BootServicesData;

    i = 0;
    var curr_start: ?u64 = null;
    var curr_end: u64 = 0;
    while (i < memory_map_size / descriptor_size) : (i += 1) {
        const desc = memory_map[i];
        const end = desc.physical_start + desc.number_of_pages * 4096;
        if (desc.type != conventional_memory and desc.type != boot_services_code and desc.type != boot_services_data) { continue; }

        if (curr_start) |start| {
            if (curr_end == desc.physical_start) {
                curr_end = end;
            } else {
                const pages = (curr_end - start) / 4096;
                serial.printf("{x:0>16}..{x:0>16} : {} (0x{x}) pages\n", .{ start, curr_end, pages, pages });
                curr_start = desc.physical_start;
                curr_end = end;
            }
        } else {
            curr_start = desc.physical_start;
            curr_end = end;
        }
    }
    if (curr_start) |start| {
        const pages = (curr_end - start) / 4096;
        serial.printf("{x:0>16}..{x:0>16} : {} ({x}) pages\n", .{ start, curr_end, pages, pages });
    }

    serial.writeText("\n\n");

    if (boot_services.exitBootServices(uefi.handle, memory_map_key) != uefi.Status.Success) {
        panic("Failed to exit boot services.", null);
    }

    if (mem) |addr| {
        return addr;
        //pmem.registerAvailableMem(addr);
    } else {
        panic("Not enough memory.", null);
    }
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

    // uefiMemory.memoryMap.refresh(); // Refresh the memory map before the exit.
    // var retCode = bootServices.exitBootServices(uefi.handle, uefiMemory.memoryMap.key);
    // if (retCode != uefi.Status.Success) {
    //     return;
    //}
    const freeSegAddr = do_exit_boot_services(bootServices);

    uefiConsole.disable(); // conOut is a boot service, so it's not available anymore.
    tty.serialPrint("Boot services exitted. UEFI console is now unavailable.\n", .{});

    tty.serialPrint("Platform initialization...\n", .{});
    platform.initialize(freeSegAddr);
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
