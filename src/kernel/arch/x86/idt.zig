const platform = @import("platform.zig");
const mem = @import("std").mem;
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const isr = @import("isr.zig");
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

// u32, u32, u32
// offset_low, selector
// flags, offset_mid
// offset_high
const IDTEntry = packed struct {
    offset_low: u16, // 0..15
    selector: u16,
    flags: u16,
    offset_mid: u16, // 16..31
    offset_high: u32, // 31..63
    zero: u32 = 0,

    fn setFlags(self: *IDTEntry, flags: IDTFlags) void {
        const flags_low: u8 = (@as(u8, flags.present) << 7) | (@as(u8, flags.privilege) << 5) | (@as(u8, flags.storage_segment) << 4) | flags.gate_type;
        self.flags = mem.nativeToBig(u16, flags_low | (0x0 << 8)); // TODO(Ryan): lol, just build correctly the flags. 0x0 := ist,zero_1.
    }

    fn setOffset(self: *IDTEntry, offset: u64) void {
        self.offset_low = @truncate(u16, offset);
        self.offset_mid = @truncate(u16, offset >> 16);
        self.offset_high = @truncate(u32, offset >> 32);
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

    idt[n].setOffset(intOffset);
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
    interrupts.register(0, divide_by_zero);
    interrupts.register(1, debug_trap);
    interrupts.register(14, page_fault_handler);
    lidt(@ptrToInt(&idtr));

    serial.writeText("IDT initialized.\n");

    runtimeTests();
}

fn divide_by_zero(ctx: *platform.Context) usize {
    serial.writeText("divide by zero!\n");
    return @ptrToInt(ctx);
}

fn debug_trap(ctx: *platform.Context) usize {
    serial.writeText("debug fault/trap\n");
    return @ptrToInt(ctx);
}

fn page_fault_handler(ctx: *platform.Context) usize {
    //serial.writeText("page fault handler\n");
    return @ptrToInt(ctx);
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
