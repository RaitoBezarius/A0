const std = @import("std");
const platform = @import("../platform.zig");

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

pub fn dumpAndAssertPlatformState(comptime print_func: anytype) void {
    if (!platform.isProtectedMode()) {
        print_func(NO_PROTECT, .{});
        platform.hang();
    }

    if (platform.isPagingEnabled()) {
        print_func(PAGING_ENABLED, .{});
    }

    if (platform.isPAEEnabled()) {
        print_func(PAE_ENABLED, .{});
    }

    if (platform.isPSEEnabled()) {
        print_func(PSE_ENABLED, .{});
    }

    if (platform.isTSSSet()) {
        print_func(WARN_TSS_SET, .{});
    }

    if (platform.isX87EmulationEnabled()) {
        print_func(WARN_EM_SET, .{});
    }

    // FIXME(Ryan): find out a way to detect CPUID.
    //if (!platform.hasCPUID()) {
    //    _ = conOut.outputString(WARN_NO_CPUID);
    //}

    if (platform.isLongModeEnabled()) {
        print_func(LONG_MODE_ENABLED, .{});
    } else {
        print_func(WARN_LONG_MODE_UNSUPPORTED, .{});
    }

    // Handle Loaded Image Protocol and print driverpoint.
    var loadedImage: *uefi.protocols.LoadedImageProtocol = undefined;
    var retCode = uefi.system_table.boot_services.?.handleProtocol(uefi.handle, &uefi.protocols.LoadedImageProtocol.guid, @ptrCast(*?*c_void, &loadedImage));
    if (retCode != uefi.Status.Success) {
        platform.hang();
    }

    print_func("Loaded image: base={x}\r\n", .{@ptrToInt(loadedImage.image_base)});
}
