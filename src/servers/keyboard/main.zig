const std = @import("std");
const lib = @import("lib");
const A0 = lib.A0;
const Message = A0.Message;
const MailboxId = A0.MailboxId;
const Keyboard = A0.Server.Keyboard;

pub const system = lib.os;

// Circular buffer to hold keypress data.
const BUFFER_SIZE = 1024;
var buffer = [_]u8{0} ** BUFFER_SIZE;
var buffer_start: usize = 0;
var buffer_end: usize = 0;

// FIXME: Severely incomplete.
const scancodes = []u8{
    0,    27,  '1', '2', '3', '4', '5', '6', '7', '8', '9',  '0', '-', '=',  8,
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p',  '[', ']', '\n', 0,
    'a',  's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,   '\\', 'z',
    'x',  'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,   '*',  0,   ' ', 0,    0,
    0,    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    '-',
    0,    0,   0,   '+', 0,   0,   0,   0,   0,   0,   0,    0,   0,   0,    0,
};

var waiting_thread: ?MailboxId = null;

const KEYBOARD_NEW_DATA = 0x64;
const KEYBOARD_GET_KEYCODE = 0x60;
const KEYBOARD_RELEASE_MASK = 0x80;

fn handleKeyEvent() void {
    const status = 0; // A0.inb(KEYBOARD_NEW_DATA);
    if ((status & 1) == 0) return;

    const scancode = 0; //A0.inb(KEYBOARD_GET_KEYCODE);
    if ((scancode & KEYBOARD_RELEASE_MASK) != 0) return;

    const char = scancodes[scancode];

    if (waiting_thread) |thread| {
        waiting_thread = null;
        //A0.send(&Message.to(thread, 0, char).as(Keyboard));
    } else {
        buffer[buffer_end] = char;
        buffer_end = (buffer_end + 1) % buffer.len;
    }
}

fn handleRead(reader: MailboxId) void {
    if (buffer_start == buffer_end) {
        waiting_thread = reader;
    } else {
        //A0.send(&Message.to(reader, 0, buffer[buffer_start]).as(Keyboard));
        buffer_start = (buffer_start + 1) % buffer.len;
    }
}

pub fn main() void {
    //A0.subscribeIRQ(1, &Keyboard);

    var message = Message.from(Keyboard);
    while (true) {
        //A0.receive(&message);

        switch (message.sender) {
            MailboxId.Kernel => handleKeyEvent(),
            else => handleRead(message.sender),
        }
    }
}
