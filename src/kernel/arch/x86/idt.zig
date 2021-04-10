const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const serial = @import("../../debug/serial.zig");

pub const INTERRUPT_GATE = 0x8E;

const IDTEntry = packed struct {
    offset_low: u16,
    selector: u16,
    zero: u8 = 0,
    flags: u8,
    offset_high: u16,
};

const IDTRegister = packed struct {
    limit: u16,
    base: *[256]IDTEntry,
};

var idt: [256]IDTEntry = undefined;

const idtr = IDTRegister{ .limit = @as(u16, @sizeOf(@TypeOf(idt))), .base = &idt };

pub fn setGate(n: u8, flags: u8, offset: fn () callconv(.C) void) void {
    const intOffset = @ptrToInt(offset);

    idt[n].offset_low = @truncate(u16, intOffset);
    idt[n].offset_high = @truncate(u16, intOffset >> 16);

    idt[n].flags = flags;

    idt[n].selector = gdt.KERNEL_CODE;
}

// Load a new IDT
fn lidt(idt_ptr: usize) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (idt_ptr)
    );
}

pub fn initialize() void {
    serial.writeText("IDT initializing...\n");

    interrupts.initialize();
    lidt(@ptrToInt(&idtr));

    serial.writeText("IDT initialized.\n");
}
