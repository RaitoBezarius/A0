const uefi = @import("std").os.uefi;
const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;

const uefiAllocator = @import("uefi/allocator.zig");
const uefiMemory = @import("uefi/memory.zig");
const uefiConsole = @import("uefi/console.zig");
const uefiSystemInfo = @import("uefi/systeminfo.zig");

const graphics = @import("graphics.zig");
//const tty = @import("tty.zig");
const platform = @import("platform.zig");
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
    uefiConsole.puts("UEFI memory and debug console setup. Exitting boot services.\r\n");

    uefiMemory.memoryMap.refresh(); // Refresh the memory map before the exit.
    var retCode = bootServices.exitBootServices(uefi.handle, uefiMemory.memoryMap.key);
    if (retCode != uefi.Status.Success) {
        return;
    }
    uefiConsole.disable(); // conOut is a boot service, so it's not available anymore.
    serial.writeText("Boot services exitted. UEFI console is now unavailable.\n");

    // graphics.selfTest();
    serial.writeText("Graphics subsystem self test completed.\n");

    // runtimeServices.set_virtual_address_map();

    serial.writeText("Platform initialization...\n");
    platform.initialize();
    serial.writeText("Platform initialized.\n");

    //mem.initialize(MEMORY_OFFSET);
    //timer.initialize(100);
    //scheduler.initialize();

    //tty.colorPrint(Color.LightBlue, "\nLoading the servers (driverspace):\n");

    // The OS is now running.
    platform.cli(); // Disable interrupts.
    //var user_stack: [1024]u64 = undefined;
    //platform.liftoff(&user_fn, &user_stack[1023]); // Go to userspace.
    platform.hlt();
}
