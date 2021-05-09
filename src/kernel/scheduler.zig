const std = @import("std");
const TaskMod = @import("task.zig");
const Task = TaskMod.Task;
const TaskState = TaskMod.TaskState;
const platform = @import("platform.zig");
const serial = @import("debug/serial.zig");
const Allocator = std.mem.Allocator;
const TailQueue = std.TailQueue;

var current_task: *Task = undefined;
var current_task_node: *TailQueue(*Task).Node = undefined;
var tasks: [256]TailQueue(*Task) = undefined;
var can_switch: bool = true;
var curTaskPriority: u8 = 0;

fn idle() void {
    // platform.ioWait();
    platform.hlt();
}

pub fn setTaskSwitching(enabled: bool) void {
    can_switch = enabled;
}

// The idle task must always be running and at the priority 255
pub fn pickNextTask(ctx: *platform.Context) usize {
    current_task.stack_pointer = @ptrToInt(ctx);

    if (!can_switch) {
        return current_task.stack_pointer;
    }
    serial.printf("current task sp: 0x{x}\n", .{current_task.stack_pointer});
    var curStopped = false;
    if (current_task.state != TaskState.Runnable) {
        curStopped = true;
    }

    while (curStopped or curTaskPriority <= current_task.priority) {
        if (tasks[curTaskPriority].pop()) |next_task_node| {
            const next_task = next_task_node.data;

            if (next_task.state == TaskState.Runnable) {
                serial.printf("picking task pid: {}, stack ptr: 0x{x}\n", .{ next_task.pid, next_task.stack_pointer });
                tasks[current_task.priority].prepend(current_task_node);

                next_task_node.prev = null;
                next_task_node.next = null;
                current_task_node = next_task_node;
                current_task = next_task;
                break; // Ok, new task scheduled
            } else {
                // The "next_task" can't be scheduled and has been paused for a at least round of the scheduler
                next_task.scheduled = false;
                // Currently, the task is lost and never resumed (TODO)
            }
        } else if (!curStopped and curTaskPriority == current_task.priority) {
            serial.writeText("No new task to be scheduled\n");
            break; // Keep the current task if no task with the same priority is scheduled
        } else if (curTaskPriority >= tasks.len) {
            serial.ppanic("No task can be scheduled, missing idle task!", .{});
        } else {
            curTaskPriority += 1;
        }
    }

    serial.writeText("handing control to selected task\n");
    return current_task.stack_pointer;
}

pub fn scheduleTaskNode(task_node: *TailQueue(*Task).Node) void {
    var task = task_node.data;
    tasks[task.priority].prepend(task_node);
    task.scheduled = true;
    if (task.priority < curTaskPriority) {
        curTaskPriority = task.priority;
    }
}

pub fn scheduleNewTask(new_task: *Task, allocator: *Allocator) Allocator.Error!void {
    var task_node = try allocator.create(TailQueue(*Task).Node);
    if (new_task.priority < curTaskPriority) {
        curTaskPriority = new_task.priority;
    }
    task_node.* = .{ .data = new_task };
    scheduleTaskNode(task_node);
}

pub fn scheduleBack(task_node: *TailQueue(*Task).Node) void {
    // Put back into the tasks array a task node
    var task = task_node.data;
    if (!task.scheduled) {
        // TODO: if waiting for a timer, remove from the timer structure
        scheduleTaskNode(task_node);
    }
}

pub fn initialize(kStackStart: usize, kStackSize: usize, allocator: *Allocator) Allocator.Error!void {
    serial.writeText("scheduler initialization...\n");
    defer serial.writeText("scheduler initialized\n");

    var iTaskQueue: u32 = 0;
    while (iTaskQueue < tasks.len) : (iTaskQueue += 1) {
        tasks[iTaskQueue] = TailQueue(*Task){};
    }

    current_task = try allocator.create(Task);
    errdefer allocator.destroy(current_task);
    current_task_node = try allocator.create(TailQueue(*Task).Node);
    errdefer allocator.destroy(current_task_node);

    // init kernel task.
    current_task.pid = 0;
    current_task.priority = 0;
    current_task.state = TaskState.Runnable;
    current_task.kernel_stack = @intToPtr([*]usize, @ptrToInt(&kStackStart))[0..kStackSize];
    current_task.user_stack = &[_]usize{};
    current_task.kernel = true;

    current_task_node.next = null;
    current_task_node.prev = null;
    current_task_node.data = current_task;

    var idle_task = try Task.create(@ptrToInt(idle), true, allocator, tasks.len - 1);
    errdefer idle_task.destroy(allocator);

    try scheduleNewTask(idle_task, allocator);
}

pub fn remove(task_node: *TailQueue(*Task).Node, allocator: *Allocator) void {
    var task = task_node.data;
    if (task.scheduled) {
        tasks[task.priority].remove(task_node);
    }
    TailQueue(*Task).destroyNode(task_node, allocator);
    task.destroy(allocator);
}

// Test
var fn1_stop: bool = false;
fn self_test_fn1() noreturn {
    serial.writeText("FN1 - 0\n");
    asm volatile ("hlt");
    serial.writeText("FN1 - 1\n");
    fn1_stop = true;
    asm volatile ("hlt");
    while (true) {
        serial.writeText("FN1\n");
        asm volatile ("hlt");
    }
}
fn self_test_fn2() noreturn {
    while (true) {
        serial.writeText("FN2\n");
        asm volatile ("hlt");
    }
}
fn self_test_fn3() noreturn {
    while (true) {
        serial.writeText("FN3\n");
        asm volatile ("hlt");
    }
}
var task_fn_1: *Task = undefined;
var task_fn_2: *Task = undefined;
var task_fn_3: *Task = undefined;
pub fn self_test_init(allocator: *Allocator) Allocator.Error!void {
    serial.writeText("scheduler self_test_init initialization...\n");
    defer serial.writeText("scheduler self_test_init initialized\n");
    task_fn_1 = try Task.create(@ptrToInt(self_test_fn1), true, allocator, 0);
    task_fn_2 = try Task.create(@ptrToInt(self_test_fn2), true, allocator, 4);
    task_fn_3 = try Task.create(@ptrToInt(self_test_fn3), true, allocator, 4);
    try scheduleNewTask(task_fn_1, allocator);
    try scheduleNewTask(task_fn_2, allocator);
    try scheduleNewTask(task_fn_3, allocator);
}
pub fn selfTest() void {
    while (true) {
        if (fn1_stop) {
            task_fn_1.state = TaskState.Stopped;
            current_task.state = TaskState.Stopped;
        }
        asm volatile ("hlt");
    }
}
