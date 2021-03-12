const std = @import("std");
const platform = @import("../platform.zig");

const L = std.unicode.utf8ToUtf16LeStringLiteral;
const uefi = std.os.uefi;

const NO_PROTECT = L("Protected mode not enabled, UEFI specification violation!\r\n");
const PAGING_ENABLED = L("Paging is enabled\r\n");
const PAE_ENABLED = L("PAE is enabled\r\n");
const PSE_ENABLED = L("PSE is enabled\r\n");
const WARN_TSS_SET = L("WARNING: task switch flag is set\r\n");
const WARN_EM_SET = L("WARNING: x87 emulation is enabled\r\n");
const LONG_MODE_ENABLED = L("Long mode is enabled\r\n");
const WARN_LONG_MODE_UNSUPPORTED = L("Long mode is unsupported\r\n");
const WARN_NO_CPUID = L("No CPUID instruction was detected, prepare for unforeseen consequences.\r\n");

pub fn dumpAndAssertPlatformState(conOut: *uefi.protocols.SimpleTextOutputProtocol) void {
    if (!platform.isProtectedMode()) {
        _ = conOut.outputString(NO_PROTECT);
        platform.hang();
    }

    if (platform.isPagingEnabled()) {
        _ = conOut.outputString(PAGING_ENABLED);
    }

    if (platform.isPAEEnabled()) {
        _ = conOut.outputString(PAE_ENABLED);
    }

    if (platform.isTSSSet()) {
        _ = conOut.outputString(WARN_TSS_SET);
    }

    if (platform.isX87EmulationEnabled()) {
        _ = conOut.outputString(WARN_EM_SET);
    }

    // FIXME(Ryan): find out a way to detect CPUID.
    //if (!platform.hasCPUID()) {
    //    _ = conOut.outputString(WARN_NO_CPUID);
    //}

    if (platform.isLongModeEnabled()) {
        _ = conOut.outputString(LONG_MODE_ENABLED);
    } else {
        _ = conOut.outputString(WARN_LONG_MODE_UNSUPPORTED);
    }

    _ = conOut.outputString(L("Platform dumped.\r\n"));
}
