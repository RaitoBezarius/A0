const std = @import("std");
const Allocator = std.mem.Allocator;
const A0 = @import("lib").A0;
const tty = @import("graphics/tty.zig");
const TaskMod = @import("task.zig");
const Task = TaskMod.Task;
const TaskState = TaskMod.TaskState;
const Message = A0.Message;
const TailQueue = std.TailQueue;
const HashMap = std.AutoHashMap;
const LinkedList = std.LinkedList;

var kAllocator: *const Allocator = undefined;
// Copy an user pointer to kernel land using transferArea.
fn userToKernel(user_ptr: usize, size: usize, transferArea: usize) usize {}
// Copy a kernel pointer to user land using transferArea.
fn kernelToUser(kernel_ptr: usize, size: usize, transferArea: usize) usize {}

pub const Mailbox = struct {
    messages: TailQueue(Message),
    waiting_queue: TailQueue(Task),

    pub fn init() Mailbox {
        return Mailbox{ .messages = TailQueue(Message){}, .waiting_queue = TailQueue(Task){} };
    }
};

var ports: HashMap(u16, *Mailbox) = undefined;

pub fn getOrCreatePort(id: u16) Allocator.Error!*Mailbox {
    if (ports.get(id)) |entry| {
        return entry.value;
    }

    const mailbox = kAllocator.createOne(Mailbox);
    mailbox.* = Mailbox.init();

    _ = ports.put(id, mailbox);
    return mailbox;
}

pub fn receive(dst: *Message) Allocator.Error!void {
    // TODO: permission/validation
    const mailbox = getMailbox(dst.receiver);

    const receivingTaskNode = scheduler.current().?;
    receivingTaskNode.data.message_target = dst;

    if (mailbox.messages.popFirst()) |first| {
        const message = first.data;
        deliverMessage(message);
        kAllocator.destroy(first);
    } else {
        // Force unschedule the task.
        scheduler.forceUnschedule(receivingTaskNode);
        receivingTask.state = TaskState.Sleep;
        mailbox.waiting_queue.append(receivingTaskNode);
    }
}

fn getMailbox(mailbox_id: MailboxId) Allocator.Error!*Mailbox {
    switch (mailbox_id) {
        MailboxId.This => &(scheduler.current().?).mailbox,
        MailboxId.Task => |pid| &(tasks.get(pid).?).mailbox,
        MailboxId.Port => |id| getOrCreatePort(id),
        else => unreachable,
    }
}

pub fn send(message: *const Message) Allocator.Error!void {
    const msgCopy = processOutgoingMessage(message.*);
    const mailbox = getMailbox(message.receiver);

    if (mailbox.waiting_queue.popFirst()) |receivingTask| {
        scheduler.scheduleBack(receivingTask);
        deliverMessage(msgCopy);
    } else {
        // Queue the message.
        const node = mailbox.messages.createNode(msgCopy, kAllocator);
        mailbox.messages.append(node);
    }
}

fn processOutgoingMessage(message: Message) Message {
    var msgCopy = message;

    switch (message.sender) {
        MailboxId.This => msgCopy.sender = MailboxId{ .Task = (scheduler.current().?).pid },
        else => {},
    }

    if (message.payload) |payload| {
        //TODO: msgCopy.payload = userToKernel(message.payload, layout.Temporary);
    }

    return msgCopy;
}

pub fn deliverMessage(message: Message) void {
    const receiverTask = scheduler.current().?;
    const dst = receiverTask.messageDestination;

    dst.* = message;

    if (message.payload) |payload| {
        // TODO: handle multiple threads?
        const dstBuffer = layout.UserMessages + (receiverTask.pid * x86.PAGE_SIZE);

        // TODO:
        // Desallocate old physical memory at dstBuffer.
        // task.vmm.map(dstBuffer, @ptrToInt(payload.ptr), PAGE_WRITE | PAGE_USER);
        // dst.payload = @intToPtr([*]u8, dstBuffer)[0..payload.len]
    }
}

pub fn initialize(allocator: *Allocator) Allocator.Error!void {
    tty.step("IPC primitives", .{});
    kAllocator = allocator;
    ports = HashMap(u16, *Mailbox).init(allocator);
    defer tty.stepOK();
}
