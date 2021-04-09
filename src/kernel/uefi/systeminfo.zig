const std = @import("std");
const platform = @import("../platform.zig");
const uefiConsole = @import("console.zig");

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const uefi = std.os.uefi;

const NO_PROTECT = L("Protected mode not enabled, UEFI specification violation!\r\n");
const PAGING_ENABLED = L("Paging is enabled\r\n");
const PAE_ENABLED = L("PAE is enabled\r\n");
const PSE_ENABLED = L("PSE is enabled\r\n");
const WARN_TSS_SET = L("WARNING: task switch flag is set\r\n");
const WARN_EM_SET = L("WARNING: x87 emulation is enabled\r\n");
const LONG_MODE_ENABLED = L("Long mode is enabled\r\n");
const WARN_LONG_MODE_UNSUPPORTED = L("Long mode is not enabled\r\n");
const WARN_NO_CPUID = L("No CPUID instruction was detected, prepare for unforeseen consequences.\r\n");

pub fn dumpAndAssertPlatformState() void {
    if (!platform.isProtectedMode()) {
        platform.hang();
    }

    if (platform.isPagingEnabled()) {}

    if (platform.isPAEEnabled()) {}

    if (platform.isPSEEnabled()) {}

    if (platform.isTSSSet()) {}

    if (platform.isX87EmulationEnabled()) {}

    // FIXME(Ryan): find out a way to detect CPUID.
    //if (!platform.hasCPUID()) {
    //    _ = conOut.outputString(WARN_NO_CPUID);
    //}

    if (platform.isLongModeEnabled()) {} else {}

    // Handle Loaded Image Protocol and print driverpoint.
    var loadedImage: *uefi.protocols.LoadedImageProtocol = undefined;
    var retCode = uefi.system_table.boot_services.?.handleProtocol(uefi.handle, &uefi.protocols.LoadedImageProtocol.guid, @ptrCast(*?*c_void, &loadedImage));
    if (retCode != uefi.Status.Success) {
        platform.hang();
    }

    var buf: [4096]u8 = undefined;
    uefiConsole.printf(buf[0..], "Loaded image: base={x}\r\n", .{@ptrToInt(loadedImage.image_base)});
}
