const irq = @import("interrupts.zig");
const platform = @import("platform.zig");
const serial = @import("../../debug/serial.zig");
const tty = @import("../../graphics/tty.zig");
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

pub var time_ns: u32 = undefined;
pub var time_under_1_ns: u32 = undefined;

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
    var reloadValue: u32 = 0x10000; // 19Hz.
    if (freq > 18) {
        if (freq < MAX_FREQUENCY) {
            reloadValue = (MAX_FREQUENCY + (freq / 2)) / freq;
        } else {
            reloadValue = 1;
        }
    }

    return reloadValue;
}

fn computeAdjustedFrequency(reloadValue: u32) u32 {
    return (MAX_FREQUENCY + (reloadValue / 2)) / reloadValue;
}

fn setupCounter(cs: CounterSelect, freq: u32, mode: u8) PitError!void {
    if (freq < 19 or freq > MAX_FREQUENCY) {
        return PitError.InvalidFrequency;
    }

    const reloadValue = computeReloadValue(freq);
    const frequency = computeAdjustedFrequency(reloadValue);

    time_ns = 1000000000 / frequency;
    time_under_1_ns = ((1000000000 % frequency) * 1000 + (frequency / 2)) / frequency;

    switch (cs) {
        .Counter0 => cur_freq_0 = frequency,
        .Counter1 => cur_freq_1 = frequency,
        .Counter2 => cur_freq_2 = frequency,
    }

    const reload_val_trunc = @truncate(u16, reloadValue);

    sendCommand(mode | OCW_READ_LOAD_DATA | cs.getCounterOCW());
    sendDataToCounter(cs, @truncate(u8, reload_val_trunc));
    sendDataToCounter(cs, @truncate(u8, reload_val_trunc >> 8));

    switch (cs) {
        .Counter0 => ticks = 0,
        .Counter1 => unused_ticks = 0,
        .Counter2 => speaker_ticks = 0,
    }

    serial.printf("Frequency set at: {d}Hz, reload value: {d}Hz, real frequency: {d}Hz\n", .{ freq, reloadValue, frequency });
}

pub fn getTicks() u64 {
    return ticks;
}

pub fn getFrequency() u32 {
    return cur_freq_0;
}

pub fn initialize() void {
    // tty.step("PIT initialization", .{});
    // defer tty.stepOK();

    // const freq: u32 = 10000;
    const freq = 500; // TODO(w): choose the best frequency

    setupCounter(CounterSelect.Counter0, freq, OCW_MODE_SQUARE_WAVE_GENERATOR | OCW_BINARY_COUNT_BINARY) catch |e| {
        serial.ppanic("Invalid frequency: {d}\n", .{freq});
    };

    irq.registerIRQ(IRQ_PIT, pitHandler);

    // TODO: runtimeTests.
}

fn runtimeTests() void {
    platform.cli();
    defer platform.sti();
    // Force enable interrupts
}
