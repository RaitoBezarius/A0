const uefi = @import("std").os.uefi;
const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;

const graphics = @import("graphics.zig");
//const tty = @import("tty.zig");
const platform = @import("platform.zig");

//fn os_banner() void {
//    const title = "A/0 - v0.0.1";
//    tty.alignCenter(title.len);
//    tty.colorPrint(Color.LightRed, title ++ "\n\n");
//
//    tty.colorPrint(Color.LightBlue, "Booting the microkernel:\n");
//}

pub fn main() void {
    graphics.initialize();
    //tty.initialize();

    //os_banner();

    // UEFI-specific initialization
    // bootServices.exit_boot_services();
    // runtimeServices.set_virtual_address_map();

    platform.initialize();
    //pmem.initialize();
    //vmem.initialize();
    //mem.initialize(MEMORY_OFFSET);
    //timer.initialize(100);
    //scheduler.initialize();

    //tty.colorPrint(Color.LightBlue, "\nLoading the servers (driverspace):\n");
    //info.loadModules();

    // The OS is now running.
    platform.sti();
    platform.hlt();
}
