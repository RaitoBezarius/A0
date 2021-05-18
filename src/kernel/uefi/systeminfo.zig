const std = @import("std");
const platform = @import("../platform.zig");
const uefiConsole = @import("console.zig");

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const uefi = std.os.uefi;

const NO_PROTECT = "Protected mode not enabled, UEFI specification violation!\r\n";
const PAGING_ENABLED = "Paging is enabled\r\n";
const PAE_ENABLED = "PAE is enabled\r\n";
const PSE_ENABLED = "PSE is enabled\r\n";
const WARN_TSS_SET = "WARNING: task switch flag is set\r\n";
const WARN_EM_SET = "WARNING: x87 emulation is enabled\r\n";
const LONG_MODE_ENABLED = "Long mode is enabled\r\n";
const WARN_LONG_MODE_UNSUPPORTED = "Long mode is not enabled\r\n";
const WARN_NO_CPUID = "No CPUID instruction was detected, prepare for unforeseen consequences.\r\n";

pub fn dumpAndAssertPlatformState() void {
    if (!platform.isProtectedMode()) {
        uefiConsole.puts(NO_PROTECT);
        platform.hang();
    }

    if (platform.isPagingEnabled()) {
        uefiConsole.puts(PAGING_ENABLED);
    }

    if (platform.isPAEEnabled()) {
        uefiConsole.puts(PAE_ENABLED);
    }

    if (platform.isPSEEnabled()) {
        uefiConsole.puts(PSE_ENABLED);
    }

    if (platform.isTSSSet()) {
        uefiConsole.puts(WARN_TSS_SET);
    }

    if (platform.isX87EmulationEnabled()) {
        uefiConsole.puts(WARN_EM_SET);
    }

    // FIXME(Ryan): find out a way to detect CPUID.
    //if (!platform.hasCPUID()) {
    //    _ = conOut.outputString(WARN_NO_CPUID);
    //}

    if (platform.isLongModeEnabled()) {
        uefiConsole.puts(LONG_MODE_ENABLED);
    } else {
        uefiConsole.puts(WARN_LONG_MODE_UNSUPPORTED);
    }

    // Handle Loaded Image Protocol and print driverpoint.
    var loadedImage: *uefi.protocols.LoadedImageProtocol = undefined;
    var retCode = uefi.system_table.boot_services.?.handleProtocol(uefi.handle, &uefi.protocols.LoadedImageProtocol.guid, @ptrCast(*?*c_void, &loadedImage));
    if (retCode != uefi.Status.Success) {
        platform.hang();
    }

    var buf: [128]u8 = undefined;
    uefiConsole.printf(buf[0..], "Loaded image: base={x}\r\n", .{@ptrToInt(loadedImage.image_base)});
}
