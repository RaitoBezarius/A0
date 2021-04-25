const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("BootX64", "src/kernel/main.zig");

    exe.addAssemblyFile("src/kernel/arch/x86/platform.s");
    exe.addAssemblyFile("src/kernel/arch/x86/vmem.s");
    exe.addAssemblyFile("src/kernel/arch/x86/gdt.s");
    exe.addAssemblyFile("src/kernel/arch/x86/isr.s");

    exe.setBuildMode(b.standardReleaseOptions());
    exe.setTarget(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });
    //exe.setLinkerScriptPath("src/kernel/arch/x86/link.ld");
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

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        "-nodefaults",
        "-serial",
        "stdio",
        "-vga",
        "std",
        //"-machine",
        //"q35,accel=kvm:tcg",
        //"-icount",
        //"shift=7,rr=record,rrfile=build/qemu_replay.bin", // Time-travelling trace.
        "-s",
        "-S",
        "-m",
        "128M",
        "-boot",
        "d",
        "-drive",
        uefi_code,
        // "-drive",
        //        "if=pflash,format=raw,file=src/uefi_vars.bin",
        "-drive",
        "format=raw,file=fat:rw:build",
        "-monitor",
        "unix:qemu-monitor-socket,server,nowait",
        "-debugcon",
        "file:build/debug.log",
        "-global",
        "isa-debugcon.iobase=0x402",
        "-d",
        "int,cpu_reset",
        "-no-reboot",
        "-no-shutdown",
    });
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&uefiStartupScript.step);

    const run = b.step("run", "run with qemu");
    run.dependOn(&run_cmd.step);
}
