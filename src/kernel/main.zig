const uefi = @import("std").os.uefi;
const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;

const uefiAllocator = @import("uefi/allocator.zig");
const uefiMemory = @import("uefi/memory.zig");
const uefiSystemInfo = @import("uefi/systeminfo.zig");

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
    uefiMemory.initialize();
    graphics.initialize();

    // UEFI-specific initialization
    const bootServices = uefi.system_table.boot_services.?;

    printf(buf[0..], "EFER MSR: {}\r\n", .{platform.readMSR(platform.EFER_MSR)});
    platform.writeMSR(platform.EFER_MSR, 1 << 8);
    uefiSystemInfo.dumpAndAssertPlatformState(con_out);

    printf(buf[0..], "Quitting boot services, memory map key: {}\r\n", .{uefiMemory.memoryMap.key});
    uefiMemory.memoryMap.refresh(); // Refresh the memory map before the exit.
    var retCode = bootServices.exitBootServices(uefi.handle, uefiMemory.memoryMap.key);

    if (retCode != uefi.Status.Success) {
        printf(buf[0..], "Failed to exit boot services, err code: {}, returning to EFI caller after input.\r\n", .{retCode});
        waitForUserInput();
        return;
    }

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
