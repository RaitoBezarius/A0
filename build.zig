const std = @import("std");
const ArrayList = std.ArrayList;
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) !void {
    const exe = b.addExecutable("BootX64", "src/kernel/main.zig");

    exe.addPackagePath("lib", "src/lib/index.zig");

    exe.addAssemblyFile("src/kernel/arch/x86/platform.s");
    exe.addAssemblyFile("src/kernel/arch/x86/gdt.s");
    exe.addAssemblyFile("src/kernel/arch/x86/isr.s");

    exe.setBuildMode(b.standardReleaseOptions());
    exe.setTarget(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });
    exe.setOutputDir("build/EFI/BOOT");
    b.default_step.dependOn(&exe.step);

    const extractDebugInfo = b.addSystemCommand(&[_][]const u8{
        "objcopy",
        "-j",
        ".text",
        "-j",
        ".debug_info",
        "-j",
        ".debug_abbrev",
        "-j",
        ".debug_loc",
        "-j",
        ".debug_ranges",
        "-j",
        ".debug_pubnames",
        "-j",
        ".debug_pubtypes",
        "-j",
        ".debug_line",
        "-j",
        ".debug_macinfo",
        "-j",
        ".debug_str",
        "--target=efi-app-x86_64",
        "build/EFI/BOOT/BootX64.efi",
        "build/EFI/BOOT/BootX64.debug",
    });
    extractDebugInfo.step.dependOn(&exe.step);
    b.default_step.dependOn(&extractDebugInfo.step);

    const uefiStartupScript = b.addWriteFile("startup.nsh", "\\EFI\\BOOT\\BootX64.efi");
    const uefi_fw_path = std.os.getenv("OVMF_FW_CODE_PATH") orelse "ovmf_code_x64.bin";

    var uefi_flag_buffer: [200]u8 = undefined;
    const uefi_code = std.fmt.bufPrint(uefi_flag_buffer[0..], "if=pflash,format=raw,readonly,file={s}", .{uefi_fw_path}) catch unreachable;

    var qemu_args_al = ArrayList([]const u8).init(b.allocator);
    defer qemu_args_al.deinit();

    const use_local_qemu = b.option(bool, "use-local-qemu", "Run the kernel using the QEMU binary in vendor/qemu/build.") orelse false;
    const disable_display = b.option(bool, "disable-display", "Disable the QEMU display.") orelse false;
    const disable_debugger = b.option(bool, "disable-debugger", "Disable the QEMU gdbserver.") orelse false;
    const disable_reboot = b.option(bool, "disable-reboot", "Disable the autoreboot mechanism, useful for triple faults debugging.") orelse true;
    const disable_shutdown = b.option(bool, "disable-shutdown", "Disable the shutdown mechanism, useful for triple faults debugging.") orelse false;
    const wait_debugger_on_startup = b.option(bool, "wait-debugger-on-startup", "Wait for debugger at startup.") orelse false;
    const debug_events = b.option([]const u8, "debug-events", "List separated by comma of QEMU debug events to use") orelse "cpu_reset";
    const guest_memory_size = b.option([]const u8, "guest-memory-size", "Amount of memory allocated to the guest VM with the <integer><size> format, e.g. 128M, 1G, etc.") orelse "128M";

    if (use_local_qemu) {
        try qemu_args_al.append("vendor/qemu/build/qemu-system-x86_64");
    } else {
        try qemu_args_al.append("qemu-system-x86_64");
    }

    try qemu_args_al.append("-nodefaults");
    try qemu_args_al.append("-serial");
    try qemu_args_al.append("stdio");
    try qemu_args_al.append("-vga");
    try qemu_args_al.append("std");

    if (disable_display) {
        try qemu_args_al.append("-display");
        try qemu_args_al.append("none");
    }

    if (!disable_debugger) {
        try qemu_args_al.append("-s");
    }

    if (wait_debugger_on_startup) {
        try qemu_args_al.append("-S");
    }

    try qemu_args_al.append("-m");
    try qemu_args_al.append(guest_memory_size);

    try qemu_args_al.append("-boot");
    try qemu_args_al.append("d");

    try qemu_args_al.append("-drive");
    try qemu_args_al.append(uefi_code);

    try qemu_args_al.append("-drive");
    try qemu_args_al.append("format=raw,file=fat:rw:build");

    try qemu_args_al.append("-monitor");
    try qemu_args_al.append("unix:qemu-monitor-socket,server,nowait");

    try qemu_args_al.append("-debugcon");
    try qemu_args_al.append("file:build/debug.log");

    try qemu_args_al.append("-global");
    try qemu_args_al.append("isa-debugcon.iobase=0x402");

    try qemu_args_al.append("-d");
    try qemu_args_al.append(debug_events);

    if (disable_reboot) {
        try qemu_args_al.append("-no-reboot");
    }

    if (disable_shutdown) {
        try qemu_args_al.append("-no-shutdown");
    }

    var qemu_args = qemu_args_al.toOwnedSlice();
    const run_cmd = b.addSystemCommand(qemu_args);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&uefiStartupScript.step);

    const run = b.step("run", "run with qemu");
    run.dependOn(&run_cmd.step);
}
