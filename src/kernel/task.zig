const std = @import("std");
const platform = @import("platform.zig");
const Allocator = std.mem.Allocator;
const ComptimeBitmap = @import("lib/bitmap.zig").ComptimeBitmap;

pub const PidBitmap = ComptimeBitmap(u128);
pub const Entrypoint = usize;
pub const STACK_SIZE: u64 = (4096 * 1024) / @sizeOf(u64); // 4KB pages.
var all_pids: PidBitmap = brk: {
    var pids = PidBitmap.init();
    _ = pids.setFirstFree() orelse unreachable;
    break :brk pids;
};

// var taskByPid: [PidBitmap.NUM_ENTRIES]?*Task = undefined;

pub const TaskState = enum(u8) {
    Runnable,
    Stopped,
    Sleep,
    SleepNoInterrupt,
    Zombie,
};

pub const Task = struct {
    pid: PidBitmap.IndexType,
    kernel_stack: []usize, // Pointer to the kernel stack, allocated @ init
    user_stack: []usize, // Pointer to the user stack, allocated @ init, empty if it's a ktask
    stack_pointer: usize, // Current sp to task
    kernel: bool, // Is it a kernel task?
    scheduled: bool,
    priority: u8,
    state: TaskState,
    timeout: u64,

    pub fn create(entrypoint: Entrypoint, kernel: bool, allocator: *Allocator, priority: u8) Allocator.Error!*Task {
        var task = try allocator.create(Task);
        errdefer allocator.destroy(task);

        const pid = allocatePid();
        errdefer freePid(pid);

        var kstack = try allocator.alloc(usize, STACK_SIZE);
        errdefer allocator.free(kstack);

        var ustack = if (kernel) &[_]usize{} else try allocator.alloc(usize, STACK_SIZE);
        errdefer if (!kernel) allocator.free(ustack);

        task.* = .{
            .pid = pid,
            .kernel_stack = kstack,
            .user_stack = ustack,
            .kernel = kernel,
            .stack_pointer = @ptrToInt(&kstack[STACK_SIZE - 1]),
            .priority = priority,
            .state = TaskState.Runnable,
            .scheduled = false,
            .timeout = 0, // In nano seconds
        };
        try platform.initializeTask(task, entrypoint, allocator);
        // taskByPid[pid] = task;

        return task;
    }

    pub fn destroy(self: *Task, allocator: *Allocator) void {
        // taskByPid[self.pid] = null;
        freePid(self.pid);

        if (@ptrToInt(self.kernel_stack.ptr) != @frameAddress()) {
            allocator.free(self.kernel_stack);
        }

        if (!self.kernel) {
            allocator.free(self.user_stack);
        }

        allocator.destroy(self);
    }
};

fn allocatePid() PidBitmap.IndexType {
    return all_pids.setFirstFree() orelse @panic("Out of PIDs");
}

fn freePid(pid: PidBitmap.IndexType) void {
    if (!all_pids.isSet(pid)) {
        @panic("PID being freed not allocated");
    }

    all_pids.clearEntry(pid);
}

// pub fn getTask(pid: PidBitmap.IndexType) ?*Task {
//     return taskByPid[pid];
// }
