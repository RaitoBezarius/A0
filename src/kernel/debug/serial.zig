const platform = @import("../platform.zig");
const out = platform.out;
const in = platform.in;

pub const SERIAL_COM1: u16 = 0x3F8;
var port: u16 = undefined;

fn configureBaudRate(com: u16, divisor: u16) void {
    // Enable DLAB
    // Expect the highest 8 bits on the data port
    // then the lowest 8 bits will follow.
    out(com + 3, @as(u8, 0x80));
    out(com, (divisor >> 8));
    out(com, divisor);
}

fn configureLine(com: u16) void {
    out(com + 3, @as(u8, 0x03));
}

fn configureBuffers(com: u16) void {
    out(com + 2, @as(u8, 0xC7));
}

fn selfTest(com: u16) void {
    out(com + 4, @as(u8, 0x1E)); // Loopback
    out(com, @as(u8, 0xAE));

    if (in(u8, com) != 0xAE) {
        platform.hang(); // Nothing to do here.
    }

    out(com + 4, @as(u8, 0x0F)); // Normal operation mode.
}

pub fn initialize(com: u16, divisor: u16) void {
    // No interrupts
    out(com + 1, @as(u8, 0x00));
    configureBaudRate(com, divisor);
    configureLine(com);
    configureBuffers(com);
    out(com + 3, @as(u8, 0x03));
    port = com;
}

fn is_transmit_empty() bool {
    return (in(u8, port + 5) & 0x20) != 0;
}

pub fn write(c: u8) void {
    while (!is_transmit_empty()) {}

    out(port, c);
}

pub fn writeText(s: []const u8) void {
    for (s) |c| {
        write(c);
    }
}

fn has_received() bool {
    return (in(u8, port + 5) & 1) != 0;
}

pub fn read() u8 {
    while (!has_received()) {}

    return in(u8, port);
}
