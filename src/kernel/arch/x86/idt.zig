const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const serial = @import("../../debug/serial.zig");

pub const IDTFlags = struct {
    gate_type: u4,
    storage_segment: u1,
    privilege: u2,
    present: u1,

    fn fromRaw(val: u8) IDTFlags {}
};

pub const InterruptGateFlags = IDTFlags{
    .gate_type = 0xE,
    .storage_segment = 0,
    .privilege = 0,
    .present = 1,
};

const IDTEntry = packed struct {
    offset_low: u16, // 0..15
    selector: u16,
    ist: u2,
    zero_1: u6 = 0,
    gate_type: u4,
    storage_segment: u1,
    privilege: u2,
    present: u1,
    offset_high: u48, // 16..63.
    zero_2: u32 = 0,

    fn setFlags(self: *IDTEntry, flags: IDTFlags) void {
        self.gate_type = flags.gate_type;
        self.storage_segment = flags.storage_segment;
        self.privilege = flags.privilege;
        self.present = flags.present;
    }
};

const IDTRegister = packed struct {
    limit: u16,
    base: *[256]IDTEntry,
};

var idt: [256]IDTEntry = undefined;

const idtr = IDTRegister{ .limit = @as(u16, @sizeOf(@TypeOf(idt))), .base = &idt };

pub fn setGate(n: u8, flags: IDTFlags, offset: fn () callconv(.C) void) void {
    const intOffset = @ptrToInt(offset);

    idt[n].offset_low = @truncate(u16, intOffset);
    idt[n].offset_high = @truncate(u48, intOffset >> 16);

    idt[n].setFlags(flags);

    idt[n].selector = gdt.KERNEL_CODE;
}

// Load a new IDT
fn lidt(idt_ptr: usize) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (idt_ptr)
    );
}

fn sidt() IDTRegister {
    var ptr = IDTRegister{ .limit = undefined, .base = undefined };
    asm volatile ("sidt %[ptr]"
        : [ptr] "=m" (ptr)
    );

    return ptr;
}

pub fn initialize() void {
    serial.writeText("IDT initializing...\n");

    interrupts.initialize();
    lidt(@ptrToInt(&idtr));

    serial.writeText("IDT initialized.\n");

    runtimeTests();
}

fn rt_loadedIDTProperly() void {
    const loaded_idt = sidt();

    if (idtr.limit != loaded_idt.limit) {
        @panic("Fatal error: IDT limit is not loaded properly: 0x{x} != 0x{x}\n");
    }

    if (idtr.base != loaded_idt.base) {
        @panic("Fatal error: IDT base is not loaded properly");
    }

    serial.writeText("Runtime tests: IDT loading tested succesfully.\n");
}

fn runtimeTests() void {
    rt_loadedIDTProperly();
}
