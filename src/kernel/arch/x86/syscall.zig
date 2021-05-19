const tty = @import("lib").graphics.Tty;
const gdt = @import("gdt.zig");
const x86 = @import("platform.zig");
const base = @import("../../syscalls/index.zig");

pub const ENOSYS = 0;
pub const STAR_MSR = 0xC0000081;
pub const LSTAR_MSR = 0xC0000082;

pub const FastSyscallContext = extern struct { registers: x86.Registers, // GP registers
syscall_number: u32 };

fn enableSystemCallExtensions(kernel_entrypoint_handler: fn () callconv(.C) usize) void {
    var sc_call_step = tty.step("Activating the system call extensions", .{});
    defer sc_call_step.ok();

    var eferMSR = x86.readMSR(x86.EFER_MSR);
    x86.writeMSR(x86.EFER_MSR, (eferMSR | 0x1)); // Enable SCE bit.
    x86.writeMSR(STAR_MSR, ((gdt.USER_BASE << 16) + gdt.KERNEL_CODE)); // GDT segment.
    x86.writeMSR(LSTAR_MSR, @ptrToInt(&kernel_entrypoint_handler)); // Entrypoint for SYSCALL.
}

export fn doSyscall(context: *FastSyscallContext) i32 {
    const n = context.syscall_number;

    if (n >= 0 and n <= 31) {
        return base.handlers[n](context);
    }

    return -ENOSYS;
}

pub fn SYSCALL(comptime function: anytype) fn (context: *FastSyscallContext) i32 {
    const signature = @typeInfo(@TypeOf(function));

    return struct {
        fn arg(regs: *Registers, comptime n: u8) @ArgType(signature, n) {
            return getArg(regs, n, @ArgType(signature, n));
        }

        fn syscall(context: *FastSyscallContext) i32 {
            const result = switch (signature.Fn.args.len) {
                0 => function(),
                1 => function(arg(context.registers, 0)),
                2 => function(arg(context.registers, 0), arg(context.registers, 1)),
                else => unreachable,
            };

            return 0;
        }
    }.syscall;
}

fn getArg(regs: *Registers, comptime n: u8, comptime T: type) T {
    const value = switch (n) {
        0 => regs.rax,
        1 => regs.rdx,
        2 => regs.rbx,
        3 => regs.rsi,
        4 => regs.rdi,
        else => unreachable,
    };

    if (T == bool) {
        return value != 0;
    } else if (@typeId(T) == TypeId.Pointer) {
        return @intToPtr(T, value);
    } else {
        return @intCast(T, value);
    }
}

extern fn syscall_entry() usize;
pub fn initialize() void {
    enableSystemCallExtensions(syscall_entry);
}
