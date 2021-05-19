const platform = @import("../platform.zig");
const Syscall = platform.Syscall;
const FastSyscallContext = Syscall.FastSyscallContext;
const SYSCALL = Syscall.SYSCALL;

pub var handlers = [_]fn (*FastSyscallContext) i32{SYSCALL(exit)};

fn exit() void {
    // destroy current process.
}
