const tty = @import("lib").graphics.Tty;
const kernelGraphics = @import("../../uefi/graphics.zig");

pub const KERNEL_CODE = 0x08;
pub const KERNEL_DATA = 0x10;
pub const USER_CODE = 0x20;
pub const USER_DATA = 0x28;
pub const OVMF_DATA = 0x30;
pub const OVMF_CODE = 0x38;
pub const TSS_LOW = 0x40;
pub const TSS_HIGH = 0x48;

pub const KERNEL_RPL = 0b00;
pub const USER_RPL = 0b11;

const KERNEL = 0x90;
const OVMF = 0x90;
const USER = 0xF0;
const CODE = 0x0A;
const DATA = 0x02;
const TSS_ACCESS = 0x89;

const LONGMODE = (1 << 1);
const PROTECTED = (1 << 2);
const BLOCKS_4K = (1 << 3);

const GDTEntry = packed struct { limit_low: u16, base_low: u16, base_mid: u8, access: u8, limit_high: u4, flags: u4, base_high: u8 };

const GDTRegister = packed struct {
    limit: u16,
    base: *const GDTEntry,
};

const TSS = packed struct { reserved0: u32 = undefined, rsp0: u64 = undefined, // Stack to use when coming to ring 0 from ring > 0
rsp1: u64 = undefined, rsp2: u64 = undefined, reserved1: u64 = undefined, ist1: u64 = undefined, ist2: u64 = undefined, ist3: u64 = undefined, ist4: u64 = undefined, ist5: u64 = undefined, ist6: u64 = undefined, ist7: u64 = undefined, reserved2: u64 = undefined, reserved3: u16 = undefined, iopb_offset: u16 = undefined };

fn makeEntry(base: usize, limit: usize, access: u8, flags: u4) GDTEntry {
    return GDTEntry{
        .limit_low = @truncate(u16, limit),
        .base_low = @truncate(u16, base),
        .base_mid = @truncate(u8, base >> 16),
        .access = @truncate(u8, access),
        .limit_high = @truncate(u4, limit >> 16),
        .flags = @truncate(u4, flags),
        .base_high = @truncate(u8, base >> 24),
    };
}

var gdt align(4) = [_]GDTEntry{
    makeEntry(0, 0, 0, 0),
    makeEntry(0, 0xFFFFF, KERNEL | CODE, LONGMODE | BLOCKS_4K), // Kernel base selector
    makeEntry(0, 0xFFFFF, KERNEL | DATA, LONGMODE | BLOCKS_4K),
    makeEntry(0, 0, 0, 0), // User base selector
    makeEntry(0, 0xFFFFF, USER | CODE, LONGMODE | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, USER | DATA, LONGMODE | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, OVMF | DATA, LONGMODE | BLOCKS_4K),
    makeEntry(0, 0xFFFFF, OVMF | CODE, LONGMODE | BLOCKS_4K),
    makeEntry(0, 0, 0, 0), // TSS low
    makeEntry(0, 0, 0, 0), // TSS high
};

var gdtr = GDTRegister{
    .limit = @as(u16, @sizeOf(@TypeOf(gdt))),
    .base = &gdt[0],
};

var tss = TSS{};

// During interruption of (driver|user)mode.
pub fn setKernelStack(rsp0: usize) void {
    tss.rsp0 = rsp0;
}

extern fn loadGDT(gdtr: *const GDTRegister) void;

// Load a new Task Register
pub fn ltr(desc: u16) void {
    asm volatile ("ltr %[desc]"
        :
        : [desc] "r" (desc)
    );
}

pub fn loadGDTAndTSS(gdt_ptr: *const GDTRegister) void {
    asm volatile (
        \\lgdt (%[gptr])
        \\mov %[tss], %%ax
        \\ltr %%ax
        \\mov %[kernel_data_segment], %%ax
        \\mov %%ax, %%ds
        \\mov %%ax, %%es
        \\mov %%ax, %%fs
        \\mov %%ax, %%gs
        \\mov %%ax, %%ss
        \\mov %[kernel_code_segment], %%rax
        \\push %%rax
        :
        : [gptr] "r" (gdt_ptr),
          [tss] "r" (@as(u16, TSS_LOW)),
          [kernel_data_segment] "i" (@as(u16, KERNEL_DATA)),
          [kernel_code_segment] "i" (@as(u16, KERNEL_CODE))
        : "memory"
    );
}

pub fn readGDT() GDTRegister {
    var gdtr_buffer: GDTRegister = undefined;

    asm volatile ("sgdt %[input]"
        : [input] "=m" (gdtr_buffer)
    );

    return gdtr_buffer;
}

pub fn initialize() void {
    var step = tty.step("GDT initialization...", .{});
    defer step.ok();
    @memset(@ptrCast([*]u8, &tss), 0, @sizeOf(TSS));
    kernelGraphics.serialPrint("gdt: TSS zeroed.\n", .{});

    // Initialize TSS.
    const tssBase = @ptrToInt(&tss);
    const lowTSSEntry = makeEntry(tssBase, @sizeOf(TSS) - 1, TSS_ACCESS, PROTECTED);
    const highTSSEntry = makeEntry(@truncate(u16, tssBase >> 48), @truncate(u16, tssBase >> 32), 0, 0);

    gdt[TSS_LOW / @sizeOf(GDTEntry)] = lowTSSEntry;
    gdt[TSS_HIGH / @sizeOf(GDTEntry)] = highTSSEntry;

    kernelGraphics.serialPrint("gdt: TSS ready.\n", .{});

    // Load the TSS segment.
    loadGDTAndTSS(&gdtr);
    kernelGraphics.serialPrint("gdt: GDT and TSS loaded.\n", .{});

    runtimeTests();
}

fn runtimeTests() void {
    rt_properlyLoadedGDT();
}

fn rt_properlyLoadedGDT() void {
    const loadedGDT = readGDT();

    if (gdtr.limit != loadedGDT.limit) {
        @panic("Fatal error: GDT limit is not properly set, loading failure.\n");
    }

    if (gdtr.base != loadedGDT.base) {
        @panic("Fatal error: GDT base is not properly set, loading failure.\n");
    }

    kernelGraphics.serialPrint("Runtime tests: GDT loading successful.\n", .{});
}
