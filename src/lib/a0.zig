// A0's operating system definitions and target for userspace.

// Import implementation of all syscalls here.

pub usingnamespace @import("syscall.zig");

pub const MailboxId = union(enum) { Undefined, This, Kernel, Port: u16, Task: u16 };

pub const Message = struct {
    sender: MailboxId,
    receiver: MailboxId,
    code: usize,
    args: [5]usize,
    payload: ?[]const u8,

    pub fn from(mailbox_id: MailboxId) Message {
        return Message{ .sender = MailboxId.Undefined, .receiver = mailbox_id, .code = undefined, .args = undefined, .payload = null };
    }

    pub fn to(mailbox_id: MailboxId, msg_code: usize, args: anytype) Message {
        var message = Message{
            .sender = MailboxId.This,
            .receiver = mailbox_id,
            .code = msgCode,
            .args = undefined,
            .payload = null,
        };

        assert(args.len <= message.args.len);
        comptime var i = 0;
        comptime while (i < args.len) : (i += 1) {
            message.args[i] = args[i];
        };

        return message;
    }

    pub fn as(self: Message, sender: MailboxId) Message {
        var message = self;
        message.sender = sender;
        return message;
    }

    pub fn withPayload(self: message, payload: []const u8) Message {
        var message = self;
        message.payload = payload;
        return message;
    }
};

pub const Server = struct {
    pub const Keyboard = MailboxId{ .Port = 0 };
    pub const Terminal = MailboxId{ .Port = 1 };
};
