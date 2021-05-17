const std = @import("std");
const TaskMod = @import("task.zig");
const Task = TaskMod.Task;
const TaskState = TaskMod.TaskState;
const platform = @import("platform.zig");
const serial = @import("debug/serial.zig");
const Allocator = std.mem.Allocator;
const TailQueue = std.TailQueue;
const TaskQueue = TailQueue(*Task);

const E_SOON_DELAY_NS: u64 = 10 * 1000 * 1000;
const E_LATE_DELAY_NS: u64 = 1000 * 1000 * 1000;

var current_task: *Task = undefined;
var current_task_node: *TaskQueue.Node = undefined;
var tasks: [256]TaskQueue = undefined;
var can_switch: bool = true;
var curTaskPriority: u8 = 0;
var taskNodeByPid: [TaskMod.PidBitmap.NUM_ENTRIES]?*TaskQueue.Node = undefined;

// Based on how the L4 microkernel works
var elapsed_ns: u64 = 0;
var e_soon = E_SOON_DELAY_NS;
var e_late = E_LATE_DELAY_NS;
var soonTimeouts: TaskQueue = TaskQueue{}; // Sorted
var lateTimeouts: TaskQueue = TaskQueue{}; // Unsorted
var farFutureTimeouts: TaskQueue = TaskQueue{}; // Unsorted

pub fn current() ?TaskQueue.Node {
    if (current_task_node == undefined) {
        return null;
    } else {
        return current_task_node;
    }
}

fn idle() void {
    // platform.ioWait();
    platform.hlt();
}

pub fn setTaskSwitching(enabled: bool) void {
    can_switch = enabled;
}

// *** Timeouts ***

fn insertSoonTimeout(task_node: *TaskQueue.Node) void {
    const timeout = task_node.data.timeout;
    var ptr: ?*TaskQueue.Node = soonTimeouts.first;
    while (ptr) |inq_task_node| {
        if (inq_task_node.data.timeout >= timeout) {
            soonTimeouts.insertBefore(inq_task_node, task_node);
            return;
        }
        ptr = task_node.next;
    }
    soonTimeouts.append(task_node);
}

pub fn putTaskToSleep(task_node: *TaskQueue.Node, timeout_delay: u64) void {
    var timeout = elapsed_ns + timeout_delay;
    forceUnschedule(task_node); // Because we need to use the task_node
    task_node.data.state = TaskState.Sleep;
    task_node.data.timeout = timeout;
    if (timeout <= e_soon) {
        insertSoonTimeout(task_node);
    } else if (timeout <= e_late) {
        lateTimeouts.append(task_node);
    } else {
        farFutureTimeouts.append(task_node);
    }
}

fn organizeTimeoutQueues() void {
    if (e_late <= elapsed_ns) {
        e_late = elapsed_ns + E_LATE_DELAY_NS;
        var ptr: ?*TaskQueue.Node = farFutureTimeouts.first;
        while (ptr) |task_node| {
            ptr = task_node.next;
            if (task_node.data.timeout <= e_late) {
                farFutureTimeouts.remove(task_node);
                lateTimeouts.append(task_node);
            }
        }
    }
    if (e_soon <= elapsed_ns) {
        e_soon = elapsed_ns + E_SOON_DELAY_NS;
        var ptr: ?*TaskQueue.Node = lateTimeouts.first;
        while (ptr) |task_node| {
            ptr = task_node.next;
            if (task_node.data.timeout <= e_soon) {
                lateTimeouts.remove(task_node);
                insertSoonTimeout(task_node);
            }
        }
    }
}

fn rescheduleTimeouts() void {
    organizeTimeoutQueues();
    while (soonTimeouts.first) |task_node| {
        if (task_node.data.timeout > elapsed_ns) {
            break;
        }
        var task_node_ptr = soonTimeouts.popFirst();
        task_node.data.timeout = 0;
        scheduleBack(task_node);
        // TODO : the task was interupted. Should we provide some informations to the task ? (On the stack, registers ?)
    }
}

fn removeTaskTimeout(task_node: *TaskQueue.Node) void {
    var task = task_node.data;
    if (task.timeout != 0) {
        organizeTimeoutQueues();
        if (task.timeout <= e_soon) {
            soonTimeouts.remove(task_node);
        } else if (task.timeout <= e_late) {
            lateTimeouts.remove(task_node);
        } else {
            farFutureTimeouts.remove(task_node);
        }
        task.timeout = 0;
    }
}

// *** Scheduler ***

fn forceUnschedule(task_node: *TaskQueue.Node) void {
    // The task state still must be set manually
    var task = task_node.data;
    if (task.scheduled) {
        task.scheduled = false;
        tasks[task.priority].remove(task_node);
    }
}

// The idle task must always be running and at the priority 255
pub fn pickNextTask(ctx: *platform.Context) usize {
    current_task.stack_pointer = @ptrToInt(ctx);

    if (!can_switch) {
        return current_task.stack_pointer;
    }
    elapsed_ns += platform.getClockInterval();
    rescheduleTimeouts();

    //serial.printf("current task sp: 0x{x}\n", .{current_task.stack_pointer});
    var curStopped = false;
    if (current_task.state != TaskState.Runnable) {
        curStopped = true;
    }

    while (curStopped or curTaskPriority <= current_task.priority) {
        if (tasks[curTaskPriority].pop()) |next_task_node| {
            const next_task = next_task_node.data;

            if (next_task.state == TaskState.Runnable) {
                //serial.printf("picking task pid: {}, stack ptr: 0x{x}\n", .{ next_task.pid, next_task.stack_pointer });
                tasks[current_task.priority].prepend(current_task_node);

                // next_task_node.prev = null;
                // next_task_node.next = null;
                current_task_node = next_task_node;
                current_task = next_task;
                break; // Ok, new task scheduled
            } else {
                // The "next_task" can't be scheduled and has been paused for a at least round of the scheduler. It will be awoken by a timer or an event
                next_task.scheduled = false;
            }
        } else if (!curStopped and curTaskPriority == current_task.priority) {
            //serial.writeText("No new task to be scheduled\n");
            break; // Keep the current task if no task with the same priority is scheduled
        } else if (curTaskPriority >= tasks.len) {
            serial.ppanic("No task can be scheduled, missing idle task!", .{});
        } else {
            curTaskPriority += 1;
        }
    }

    //serial.writeText("handing control to selected task\n");
    return current_task.stack_pointer;
}

fn scheduleTaskNode(task_node: *TaskQueue.Node) void {
    var task = task_node.data;
    tasks[task.priority].prepend(task_node);
    task.scheduled = true;
    if (task.priority < curTaskPriority) {
        curTaskPriority = task.priority;
    }
}

pub fn scheduleNewTask(new_task: *Task, allocator: *Allocator) Allocator.Error!void {
    var task_node = try allocator.create(TaskQueue.Node);
    if (new_task.priority < curTaskPriority) {
        curTaskPriority = new_task.priority;
    }
    task_node.* = .{ .data = new_task };
    taskNodeByPid[new_task.pid] = task_node;
    scheduleTaskNode(task_node);
}

pub fn scheduleBack(task_node: *TaskQueue.Node) void {
    // Put back into the tasks array a task node
    removeTaskTimeout(task_node);
    task_node.data.state = TaskState.Runnable;
    if (!task_node.data.scheduled) {
        // If the task was unscheduled for a short time, may stil be in the queue
        scheduleTaskNode(task_node);
    }
}

pub fn initialize(kStackStart: usize, kStackSize: usize, allocator: *Allocator) Allocator.Error!void {
    serial.writeText("scheduler initialization...\n");
    defer serial.writeText("scheduler initialized\n");

    var iTaskQueue: u32 = 0;
    while (iTaskQueue < tasks.len) : (iTaskQueue += 1) {
        tasks[iTaskQueue] = TaskQueue{};
    }

    current_task = try allocator.create(Task);
    errdefer allocator.destroy(current_task);
    current_task_node = try allocator.create(TaskQueue.Node);
    errdefer allocator.destroy(current_task_node);

    // init kernel task.
    current_task.* = .{
        .pid = 0,
        .kernel_stack = @intToPtr([*]usize, @ptrToInt(&kStackStart))[0..kStackSize],
        .user_stack = &[_]usize{},
        .kernel = true,
        .stack_pointer = undefined,
        .priority = 0,
        .state = TaskState.Runnable,
        .scheduled = false,
        .timeout = 0,
        .mailbox = Mailbox.init(),
        .message_target = undefined,
    };
    current_task_node.data = current_task;

    var idle_task = try Task.create(@ptrToInt(idle), true, allocator, tasks.len - 1);
    errdefer idle_task.destroy(allocator);

    try scheduleNewTask(idle_task, allocator);
}

pub fn getTaskNode(pid: TaskMod.PidBitmap.IndexType) ?*TaskQueue.Node {
    return taskNodeByPid[pid];
}

pub fn remove(task_node: *TaskQueue.Node, allocator: *Allocator) void {
    removeTaskTimeout(task_node);
    forceUnschedule(task_node);
    taskNodeByPid[task_node.data.pid] = null;
    task_node.data.destroy(allocator);
    allocator.destroy(task_node);
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
fn self_test_timeout() noreturn {
    while (true) {
        serial.writeText("==== TIMEOUT OK ===\n");
        asm volatile ("hlt");
    }
}
var task_fn_1: *Task = undefined;
var task_fn_2: *Task = undefined;
var task_fn_3: *Task = undefined;
var task_fn_timeout: *Task = undefined;
pub fn self_test_init(allocator: *Allocator) Allocator.Error!void {
    serial.writeText("scheduler self_test_init initialization...\n");
    defer serial.writeText("scheduler self_test_init initialized\n");
    task_fn_1 = try Task.create(@ptrToInt(self_test_fn1), true, allocator, 0);
    task_fn_2 = try Task.create(@ptrToInt(self_test_fn2), true, allocator, 4);
    task_fn_3 = try Task.create(@ptrToInt(self_test_fn3), true, allocator, 4);
    task_fn_timeout = try Task.create(@ptrToInt(self_test_timeout), true, allocator, 4);
    try scheduleNewTask(task_fn_1, allocator);
    try scheduleNewTask(task_fn_2, allocator);
    try scheduleNewTask(task_fn_3, allocator);
    try scheduleNewTask(task_fn_timeout, allocator);

    // remove(getTaskNode(task_fn_3.pid).?, allocator);
}
pub fn selfTest() void {
    var timeout_node = getTaskNode(task_fn_timeout.pid).?;
    putTaskToSleep(timeout_node, 2 * 1000 * 1000 * 1000);

    while (!fn1_stop) {
        asm volatile ("hlt");
    }
    task_fn_1.state = TaskState.Stopped;
    current_task.state = TaskState.Stopped;
    while (true) {
        asm volatile ("hlt");
    }
}
