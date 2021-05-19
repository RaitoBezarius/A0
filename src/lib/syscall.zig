pub usingnamespace @import("arch/x86_64/syscall.zig");
pub fn exit(status: i32) noreturn {
    _ = syscall1(.exit, @bitCast(usize, @as(isize, status)));
    unreachable;
}
