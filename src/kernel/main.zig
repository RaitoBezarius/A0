const uefi = @import("std").os.uefi;
const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;

const graphics = @import("graphics.zig");
//const tty = @import("tty.zig");
const platform = @import("platform.zig");
const fmt = @import("std").fmt;
const Color = @import("color.zig").Color;

//fn os_banner() void {
//    const title = "A/0 - v0.0.1";
//    tty.alignCenter(title.len);
//    tty.colorPrint(Color.LightRed, title ++ "\n\n");
//
//    tty.colorPrint(Color.LightBlue, "Booting the microkernel:\n");
//}

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;

fn puts(msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2]u16{ c, 0 }; // work around https://github.com/ziglang/zig/issues/4372
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

fn printf(buf: []u8, comptime format: []const u8, args: anytype) void {
    puts(fmt.bufPrint(buf, format, args) catch unreachable);
}

fn showMemoryMapInfo(memory_map: [*]uefi.tables.MemoryDescriptor, memory_map_size: usize, descriptor_size: usize) void {
    var buf: [256]u8 = undefined;

    var i: usize = 0;
    while (i < memory_map_size / descriptor_size) : (i += 1) {
        // See the UEFI specification for more information on the attributes.
        printf(buf[0..], "*** {:3} type={s:23} physical=0x{x:0>16} virtual=0x{x:0>16} pages={:16} uc={} wc={} wt={} wb={} uce={} wp={} rp={} xp={} nv={} more_reliable={} ro={} sp={} cpu_crypto={} memory_runtime={}\r\n", .{
            i,
            @tagName(memory_map[i].type),
            memory_map[i].physical_start,
            memory_map[i].virtual_start,
            memory_map[i].number_of_pages,
            @boolToInt(memory_map[i].attribute.uc),
            @boolToInt(memory_map[i].attribute.wc),
            @boolToInt(memory_map[i].attribute.wt),
            @boolToInt(memory_map[i].attribute.wb),
            @boolToInt(memory_map[i].attribute.uce),
            @boolToInt(memory_map[i].attribute.wp),
            @boolToInt(memory_map[i].attribute.rp),
            @boolToInt(memory_map[i].attribute.xp),
            @boolToInt(memory_map[i].attribute.nv),
            @boolToInt(memory_map[i].attribute.more_reliable),
            @boolToInt(memory_map[i].attribute.ro),
            @boolToInt(memory_map[i].attribute.sp),
            @boolToInt(memory_map[i].attribute.cpu_crypto),
            @boolToInt(memory_map[i].attribute.memory_runtime),
        });
    }
}

pub fn nanosleep(ns: u64) void {
    _ = uefi.system_table.boot_services.?.stall(ns);
}

pub fn microsleep(ms: u64) void {
    nanosleep(ms * 1000);
}

pub fn sleep(s: u64) void {
    microsleep(s * 1000);
}

var con_in: *uefi.protocols.SimpleTextInputProtocol = undefined;
pub fn waitForUserInput() void {
    var key: uefi.protocols.InputKey = undefined;
    while (con_in.readKeyStroke(&key) != uefi.Status.Success) {}
}

pub fn main() void {
    con_out = uefi.system_table.con_out.?;
    con_in = uefi.system_table.con_in.?;
    var buf: [256]u8 = undefined;

    // FIXME(Ryan): complete the Graphics & TTY kernel impl to enable scrolling.
    // Then reuse it for everything else.

    graphics.initialize();
    //tty.initialize();

    //os_banner();

    // UEFI-specific initialization
    const bootServices = uefi.system_table.boot_services.?;

    var memoryMap: [*]uefi.tables.MemoryDescriptor = undefined;
    var memoryMapSize: usize = 0;
    var memoryMapKey: usize = undefined;
    var descriptorSize: usize = undefined;
    var descriptorVersion: u32 = undefined;

    while (bootServices.getMemoryMap(&memoryMapSize, memoryMap, &memoryMapKey, &descriptorSize, &descriptorVersion) == uefi.Status.BufferTooSmall) {
        const retCode = bootServices.allocatePool(uefi.tables.MemoryType.BootServicesData, memoryMapSize, @ptrCast(*[*]align(8) u8, &memoryMap));
        if (retCode != uefi.Status.Success) {
            printf(buf[0..], "Failed to allocate {} bytes using UEFI preboot allocator, returning to EFI caller after input.\r\n", .{retCode});
            waitForUserInput();
            return;
        }
    }

    //showMemoryMapInfo(memoryMap, memoryMapSize, descriptorSize);

    printf(buf[0..], "Quitting boot services, memory map key: {}\r\n", .{memoryMapKey});
    while (bootServices.getMemoryMap(&memoryMapSize, memoryMap, &memoryMapKey, &descriptorSize, &descriptorVersion) == uefi.Status.BufferTooSmall) {
        const retCode = bootServices.allocatePool(uefi.tables.MemoryType.BootServicesData, memoryMapSize, @ptrCast(*[*]align(8) u8, &memoryMap));
        if (retCode != uefi.Status.Success) {
            printf(buf[0..], "Failed to allocate {} bytes using UEFI preboot allocator, returning to EFI caller after input.\r\n", .{retCode});
            waitForUserInput();
            return;
        }
    }

    graphics.drawChar('A', Color.White, Color.Black);

    puts("Waiting for user input for next step.\r\n");
    waitForUserInput();

    var retCode = bootServices.exitBootServices(uefi.handle, memoryMapKey);

    if (retCode != uefi.Status.Success) {
        printf(buf[0..], "Failed to exit boot services, err code: {}, returning to EFI caller after input.\r\n", .{retCode});
        waitForUserInput();
        return;
    }

    // show_logo();
    // tty.initialize();
    // runtimeServices.set_virtual_address_map();

    platform.initialize();
    //pmem.initialize();
    //vmem.initialize();
    //mem.initialize(MEMORY_OFFSET);
    //timer.initialize(100);
    //scheduler.initialize();

    //tty.colorPrint(Color.LightBlue, "\nLoading the servers (driverspace):\n");

    // The OS is now running.
    platform.sti();
    platform.hlt();
}
