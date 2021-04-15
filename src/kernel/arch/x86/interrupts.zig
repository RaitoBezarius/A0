const out = @import("platform.zig").out;
const in = @import("platform.zig").in;
const isr = @import("isr.zig");
const x86 = @import("platform.zig");
const sti = x86.sti;
const hlt = x86.hlt;
const serial = @import("../../debug/serial.zig");

const PIC1_CMD = 0x20;
const PIC1_DATA = 0x21;
const PIC2_CMD = 0xA0;
const PIC2_DATA = 0xA1;

const ISR_READ = @as(u8, 0x0B);
const EOI = @as(u8, 0x20);

const ICW1_INIT = @as(u8, 0x10);
const ICW1_ICW4 = @as(u8, 0x01);
const ICW4_8086 = @as(u8, 0x01);

const EXCEPTION_0 = @as(u8, 0);
const EXCEPTION_31 = EXCEPTION_0 + 31;

const IRQ_0 = EXCEPTION_31 + 1;
const IRQ_15 = IRQ_0 + 15;

var handlers = [_]fn () void{unhandled} ** 48;

fn unhandled() noreturn {
    const n = isr.context.interrupt_n;

    if (n >= IRQ_0) {
        serial.ppanic("unhandled IRQ number: {d}", .{n - IRQ_0});
    } else {
        serial.ppanic("unhandled exception number: {d}", .{n});
    }
}

export fn interruptDispatch() void {
    serial.writeText("!!!! INTERRUPT DISPATCH !!!!\n");
    const n = @truncate(u8, isr.context.interrupt_n);

    switch (n) {
        EXCEPTION_0...EXCEPTION_31 => {
            handlers[n]();
        },
        IRQ_0...IRQ_15 => {
            const irq = n - IRQ_0;
            if (spuriousIRQ(n)) return;
            handlers[n]();
            signalEndOfInterrupt(n);
        },
        else => unreachable,
    }

    sti();
    hlt();
}

fn spuriousIRQ(irq: u8) bool {
    if (irq != 7) return false;

    out(PIC1_CMD, ISR_READ);
    const in_service = in(u8, PIC1_CMD);

    return (in_service & (1 << 7)) == 0;
}

fn signalEndOfInterrupt(irq: u8) void {
    if (irq >= 8) {
        out(PIC2_CMD, EOI);
    }

    out(PIC1_CMD, EOI);
}

pub fn register(n: u8, handler: fn () void) void {
    handlers[n] = handler;
}

pub fn registerIRQ(irq: u8, handler: fn () void) void {
    register(IRQ_0 + irq, handler);
    maskIRQ(irq, false);
}

pub fn maskIRQ(irq: u8, mask: bool) void {
    const port = if (irq < 8) @as(u16, PIC1_DATA) else @as(u16, PIC2_DATA);
    const old = in(u8, port);

    const shift = @truncate(u3, irq % 8);
    if (mask) {
        out(port, old | (@as(u8, 1) << shift));
    } else {
        out(port, old & ~(@as(u8, 1) << shift));
    }
}

fn remapPIC() void {
    out(PIC1_CMD, ICW1_INIT | ICW1_ICW4);
    out(PIC2_CMD, ICW1_INIT | ICW1_ICW4);

    out(PIC1_DATA, IRQ_0);
    out(PIC2_DATA, IRQ_0 + 8);

    out(PIC1_DATA, @as(u8, 1 << 2));
    out(PIC2_DATA, @as(u8, 2));

    out(PIC1_DATA, ICW4_8086);
    out(PIC2_DATA, ICW4_8086);

    out(PIC1_DATA, @as(u8, 0xFF));
    out(PIC2_DATA, @as(u8, 0xFF));
}

pub fn initialize() void {
    serial.writeText("Remapping PICs...\n");
    remapPIC();
    serial.writeText("PICs remapped.\n");
    isr.install_exceptions();
    serial.writeText("Exceptions installed.\n");
    isr.install_irqs();
    serial.writeText("IRQs installed.\n");
}
