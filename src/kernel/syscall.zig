pub const Syscall = enum(usize) { exit = 0, send = 1, receive = 2, subscribeIRQ = 3, inb = 4, outb = 5, map = 6, createTask = 7 };

fn exit(status: usize) void {
    // scheduler kill the current task.
}
