const irq = @import("interrupts.zig");
const platform = @import("platform.zig");
const serial = @import("../../debug/serial.zig");
const scheduler = @import("../../scheduler.zig");

const IRQ_PIT = 0x00;

const CounterSelect = enum {
    Counter0,
    Counter1,
    Counter2,
    pub fn getRegister(c: CounterSelect) u16 {
        return switch (c) {
            .Counter0 => 0x40, // System clock.
            .Counter1 => 0x41, // Unused.
            .Counter2 => 0x42, // PC speakers.
        };
    }

    pub fn getCounterOCW(c: CounterSelect) u8 {
        return switch (c) {
            .Counter0 => 0x00,
            .Counter1 => 0x40,
            .Counter2 => 0x80,
        };
    }
};

const PitError = error{InvalidFrequency};

const COMMAND_REGISTER: u16 = 0x43;

const OCW_BINARY_COUNT_BINARY: u8 = 0x00;
const OCW_BINARY_COUNT_BCD: u8 = 0x00; // Binary Coded Decimal
const OCW_MODE_TERMINAL_COUNT: u8 = 0x00;
const OCW_MODE_ONE_SHOT: u8 = 0x02;
const OCW_MODE_RATE_GENERATOR: u8 = 0x04;
const OCW_MODE_SQUARE_WAVE_GENERATOR: u8 = 0x06;
const OCW_MODE_SOFTWARE_TRIGGER: u8 = 0x08;
const OCW_MODE_HARDWARE_TRIGGER: u8 = 0x0A;

const OCW_READ_LOAD_LATCH: u8 = 0x00;
const OCW_READ_LOAD_LSB_ONLY: u8 = 0x10;
const OCW_READ_LOAD_MSB_ONLY: u8 = 0x20;
const OCW_READ_LOAD_DATA: u8 = 0x30;

const MAX_FREQUENCY: u32 = 1193180;

var ticks: u64 = 0;
var unused_ticks: u64 = 0; // Counter 1
var speaker_ticks: u64 = 0;

var cur_freq_0: u32 = undefined;
var cur_freq_1: u32 = undefined;
var cur_freq_2: u32 = undefined;

var time_ns: u32 = undefined;
var time_under_1_ns: u32 = undefined;

fn sendCommand(cmd: u8) void {
    platform.out(COMMAND_REGISTER, cmd);
}

fn readBackCommand(cs: CounterSelect) u8 {
    sendCommand(0xC2);
    return platform.in(u8, cs.getRegister()) & 0x3F;
}

fn sendDataToCounter(cs: CounterSelect, data: u8) void {
    platform.out(cs.getRegister(), data);
}

fn pitHandler(ctx: *platform.Context) usize {
    ticks +%= 1;

    return scheduler.pickNextTask(ctx);
}

fn computeReloadValue(freq: u32) u32 {
    var reload_value: u32 = 0x10000; // 19Hz.
    if (freq > 18) {
        if (freq < MAX_FREQUENCY) {
            reload_value = (MAX_FREQUENCY + (freq / 2)) / freq;
        } else {
            reload_value = 1;
        }
    }

    return reload_value;
}

fn computeAdjustedFrequency(reload_value: u32) u32 {
    return (MAX_FREQUENCY + (reload_value / 2)) / reload_value;
}

fn setupCounter(cs: CounterSelect, freq: u32, mode: u8) PitError!void {
    if (freq < 19 or freq > MAX_FREQUENCY) {
        return PitError.InvalidFrequency;
    }

    const reload_value = computeReloadValue(freq);
    const frequency = computeAdjustedFrequency(reload_value);

    time_ns = 1000000000 / frequency;
    time_under_1_ns = ((1000000000 % frequency) * 1000 + (frequency / 2)) / frequency;

    switch (cs) {
        .Counter0 => cur_freq_0 = frequency,
        .Counter1 => cur_freq_1 = frequency,
        .Counter2 => cur_freq_2 = frequency,
    }

    const reload_val_trunc = @truncate(u16, reload_value);

    sendCommand(mode | OCW_READ_LOAD_DATA | cs.getCounterOCW());
    sendDataToCounter(cs, @truncate(u8, reload_val_trunc));
    sendDataToCounter(cs, @truncate(u8, reload_val_trunc >> 8));

    switch (cs) {
        .Counter0 => ticks = 0,
        .Counter1 => unused_ticks = 0,
        .Counter2 => speaker_ticks = 0,
    }
}

pub fn getTicks() u64 {
    return ticks;
}

pub fn getFrequency() u32 {
    return cur_freq_0;
}

pub fn initialize() void {
    var buf: [4096]u8 = undefined;
    serial.writeText("PIT initialization\n");
    defer serial.writeText("PIT initialized.\n");

    const freq: u32 = 10000;

    //setupCounter(CounterSelect.Counter0, freq, OCW_MODE_SQUARE_WAVE_GENERATOR | OCW_BINARY_COUNT_BINARY) catch |e| {
    //    serial.ppanic("Invalid frequency: {d}\n", .{freq});
    //};
    //

    const divisor = MAX_FREQUENCY / freq;
    platform.out(0x43, @as(u8, 0x36));
    platform.out(0x40, @truncate(u8, divisor));
    platform.out(0x40, @truncate(u8, divisor >> 8));
    const reloadValue = computeReloadValue(freq);
    const adjustedFreq = computeAdjustedFrequency(reloadValue);

    // serial.printf(buf[0..], "Frequency set at: {d}Hz, reload value: {d}Hz, real frequency: {d}Hz\n", .{ freq, reloadValue, adjustedFreq });

    irq.registerIRQ(IRQ_PIT, pitHandler);

    // TODO: runtimeTests.
}

fn runtimeTests() void {
    platform.cli();
    defer platform.sti();
    // Force enable interrupts
}
