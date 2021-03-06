const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("BootX64", "src/kernel/main.zig");
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setTarget(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });
    exe.setOutputDir("build/EFI/BOOT");
    b.default_step.dependOn(&exe.step);

    const uefiStartupScript = b.addWriteFile("startup.nsh", "\\EFI\\BOOT\\BootX64.efi");

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        "-nodefaults",
        "-vga",
        "std",
        "-machine",
        "q35,accel=kvm:tcg",
        "-m",
        "128M",
        "-drive",
        "if=pflash,format=raw,readonly,file=/usr/share/ovmf/ovmf_code_x64.bin",
        "-drive",
        "if=pflash,format=raw,file=src/uefi_vars.bin",
        "-drive",
        "format=raw,file=fat:rw:build",
    });
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&uefiStartupScript.step);

    const run = b.step("run", "run with qemu");
    run.dependOn(&run_cmd.step);
}
