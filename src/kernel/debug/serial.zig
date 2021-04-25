const builtin = @import("builtin");
const std = @import("std");
const dwarf = std.dwarf;
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

pub fn printf(comptime format: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    writeText(std.fmt.bufPrint(buf[0..], format, args) catch unreachable);
}

fn has_received() bool {
    return (in(u8, port + 5) & 1) != 0;
}

pub fn read() u8 {
    while (!has_received()) {}

    return in(u8, port);
}

fn hang() noreturn {
    while (true) {}
}

var kernel_panic_allocator_bytes: [100 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = &kernel_panic_allocator_state.allocator;

extern var __debug_info_start: u8;
extern var __debug_info_end: u8;
extern var __debug_abbrev_start: u8;
extern var __debug_abbrev_end: u8;
extern var __debug_str_start: u8;
extern var __debug_str_end: u8;
extern var __debug_line_start: u8;
extern var __debug_line_end: u8;
extern var __debug_ranges_start: u8;
extern var __debug_ranges_end: u8;

fn dwarfSectionFromSymbolAbs(start: *u8, end: *u8) dwarf.DwarfInfo.Section {
    return dwarf.DwarfInfo.Section{
        .offset = 0,
        .size = @ptrToInt(end) - @ptrToInt(start),
    };
}

fn dwarfSectionFromSymbol(start: *u8, end: *u8) []const u8 {
    return @ptrCast([*]u8, start)[0 .. (@ptrToInt(end) - @ptrToInt(start)) / @sizeOf(u8)];
}

fn getSelfDebugInfo() !*dwarf.DwarfInfo {
    const S = struct {
        var have_self_debug_info = false;
        var self_debug_info: dwarf.DwarfInfo = undefined;
    };
    if (S.have_self_debug_info) return &S.self_debug_info;

    S.self_debug_info = dwarf.DwarfInfo{
        .endian = builtin.Endian.Little,
        .debug_info = dwarfSectionFromSymbol(&__debug_info_start, &__debug_info_end),
        .debug_abbrev = dwarfSectionFromSymbol(&__debug_abbrev_start, &__debug_abbrev_end),
        .debug_str = dwarfSectionFromSymbol(&__debug_str_start, &__debug_str_end),
        .debug_line = dwarfSectionFromSymbol(&__debug_line_start, &__debug_line_end),
        .debug_ranges = dwarfSectionFromSymbol(&__debug_ranges_start, &__debug_ranges_end),
    };
    try dwarf.openDwarfDebugInfo(&S.self_debug_info, kernel_panic_allocator);
    return &S.self_debug_info;
}

pub fn ppanic(comptime format: []const u8, args: anytype) noreturn {
    var buf: [4096]u8 = undefined;

    panic(std.fmt.bufPrint(buf[0..], format, args) catch unreachable, null);
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    writeText("\n!!!!!!!!!!!!! KERNEL PANIC !!!!!!!!!!!!!!!\n");
    writeText(msg);
    writeText("\n");
    hang();
}

fn printLineFromFile(_: anytype, line_info: dwarf.LineInfo) anyerror!void {
    writeText("TODO: print line from file\n");
}
