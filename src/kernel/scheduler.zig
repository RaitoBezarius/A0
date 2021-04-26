const std = @import("std");
const Task = @import("task.zig").Task;
const platform = @import("platform.zig");
const serial = @import("debug/serial.zig");
const Allocator = std.mem.Allocator;
const TailQueue = std.TailQueue;

var current_task: *Task = undefined;
var tasks: TailQueue(*Task) = undefined;
var can_switch: bool = true;

fn idle() void {
    platform.ioWait();
}

pub fn setTaskSwitching(enabled: bool) void {
    can_switch = enabled;
}

pub fn pickNextTask(ctx: *platform.Context) usize {
    current_task.stack_pointer = @ptrToInt(ctx);

    if (!can_switch) {
        return current_task.stack_pointer;
    }

    serial.printf("current task sp: 0x{x}\n", .{current_task.stack_pointer});
    if (tasks.pop()) |next_task_node| {
        const next_task = next_task_node.data;
        serial.printf("picking task pid: {}, stack ptr: 0x{x}\n", .{ next_task.pid, next_task.stack_pointer });

        next_task_node.data = current_task;
        next_task_node.prev = null;
        next_task_node.next = null;

        tasks.prepend(next_task_node);

        current_task = next_task;
    } else {
        serial.writeText("no task to pick up\n");
    }

    serial.writeText("handing control to selected task\n");
    return current_task.stack_pointer;
}

pub fn scheduleTask(new_task: *Task, allocator: *Allocator) Allocator.Error!void {
    var task_node = try allocator.create(TailQueue(*Task).Node);
    task_node.* = .{ .data = new_task };
    tasks.prepend(task_node);
}

pub fn initialize(kStackStart: usize, kStackSize: usize, allocator: *Allocator) Allocator.Error!void {
    serial.writeText("scheduler initialization...\n");
    defer serial.writeText("scheduler initialized\n");
    tasks = TailQueue(*Task){};

    current_task = try allocator.create(Task);
    errdefer allocator.destroy(current_task);

    // init kernel task.
    current_task.pid = 0;
    current_task.kernel_stack = @intToPtr([*]usize, @ptrToInt(&kStackStart))[0..kStackSize];
    current_task.user_stack = &[_]usize{};
    current_task.kernel = true;

    var idle_task = try Task.create(@ptrToInt(idle), true, allocator);
    errdefer idle_task.destroy(allocator);

    try scheduleTask(idle_task, allocator);
}
