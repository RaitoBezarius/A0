const std = @import("std");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const layout = @import("layout.zig");
const pmem = @import("pmem.zig");
const vmem = @import("vmem.zig");
const pit = @import("pit.zig");
const serial = @import("../../debug/serial.zig");
const Task = @import("../../task.zig").Task;
const Allocator = std.mem.Allocator;
const KernelAllocator = @import("KernelAllocator.zig");

pub extern fn getEflags() u32;
pub extern fn getCS() u32;

// CPU context
// Valid wrt interruptions.
// TODO: support SYSENTER.
pub const Context = extern struct {
    registers: Registers, // General purpose registers.

    interrupt_n: u64, // Number of the interrupt.
    error_code: u64, // Associated error code (or 0).

    // CPU status:
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,

    pub fn setReturnValue(self: *volatile Context, value: anytype) void {
        self.registers.rax = if (@TypeOf(value) == bool) @boolToInt(value) else @as(u64, value);
    }
};

// Structure holding general purpose registers
// Valid wrt to isrCommon.
pub const Registers = extern struct { r11: u64, r10: u64, r9: u64, r8: u64, rcx: u64, rdx: u64, rsi: u64, rdi: u64, rax: u64, rbp: u64 };

pub fn preinitialize() void {
    cli(); // Disable all interrupts.
    gdt.initialize();
    idt.initialize();
    // TODO: support for syscall require to load the kernel entrypoint in the LSTAR MSR.
}

// Takes the base address of a segment that should contain at least REQUIRED_PAGES_COUNT pages
// Returns the kernel allocator
pub fn initialize(freeSegAddr: u64, freeSegLen: u64) *Allocator {
    if (freeSegLen < layout.REQUIRED_PAGES_COUNT) {
        serial.panic("Not enough memory !", null);
    }

    pmem.initialize(freeSegAddr);
    vmem.initialize();
    pit.initialize();
    sti();
    enableSystemCallExtensions();
    // TODO: timer.initialize();
    // rtc.initialize();
    KernelAllocator.initialize(vmem.LinearAddress.four_level_addr(256, 0, 1, 0, 0));
    return &KernelAllocator.kernelAllocator;
}

pub fn initializeTask(task: *Task, entrypoint: usize, allocator: *Allocator) Allocator.Error!void {
    const dataOffset: usize = if (task.kernel) gdt.KERNEL_DATA else gdt.USER_DATA | 0b11;
    const codeOffset: usize = if (task.kernel) gdt.KERNEL_CODE else gdt.USER_CODE | 0b11;

    const kStackBottom = (if (task.kernel) task.kernel_stack.len - 17 else task.kernel_stack.len - 19) - 20;

    var stack = &task.kernel_stack;

    // 9 zero Registers: r11, r10, r9, r8, rdi, rsi, rdx, rcx, rax
    comptime var i = 0;
    inline while (i <= 8) : (i += 1) {
        stack.*[kStackBottom + i] = 0;
    }
    // Base stack pointer
    stack.*[kStackBottom + i + 0] = @ptrToInt(&stack.*[stack.len - 1]);
    // Int num
    stack.*[kStackBottom + i + 1] = 0;
    // Error code
    stack.*[kStackBottom + i + 2] = 0;
    // Reload data segment?
    stack.*[kStackBottom + i + 3] = entrypoint; // RIP
    stack.*[kStackBottom + i + 4] = codeOffset; // CS
    stack.*[kStackBottom + i + 5] = 0x202; // RFLAGS
    stack.*[kStackBottom + i + 6] = stack.*[kStackBottom + i]; // RSP
    stack.*[kStackBottom + i + 7] = 0; // SS

    // TODO(Ryan): handle when this is not a ktask and use virtual memory.
    task.stack_pointer = @ptrToInt(&stack.*[kStackBottom]);
}

pub fn liftoff(userspace_fun_ptr: *const fn () void, userspace_stack: *u64) void {
    serial.printf("Liftoff to ptr: {x}, stack: {x}\n", .{ userspace_fun_ptr, userspace_stack });
    // Get a new IP/SP and setup eflags.
    // Then sysret!
    asm volatile (
        \\mov %[userspace_fun_ptr], %%rcx
        \\mov %[userspace_stack], %%rsp
        \\mov $0x0202, %%r11
        \\sysretq
        :
        : [userspace_fun_ptr] "r" (userspace_fun_ptr),
          [userspace_stack] "r" (userspace_stack)
        : "rsp", "rcx", "r11"
    );
}

pub fn hlt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

pub fn cli() void {
    asm volatile ("cli");
}

pub fn sti() void {
    asm volatile ("sti");
}

pub fn hang() noreturn {
    cli();
    hlt();
}

pub fn readCR(comptime number: []const u8) usize {
    return asm volatile ("mov %%cr" ++ number ++ ", %[ret]"
        : [ret] "=r" (-> usize)
    );
}

pub fn writeCR(comptime number: []const u8, value: usize) void {
    asm volatile ("mov %[value], %%cr" ++ number
        :
        : [value] "r" (value)
    );
}

pub fn isProtectedMode() bool {
    const cr0 = readCR("0");
    return (cr0 & 1) == 1;
}

pub fn isPagingEnabled() bool {
    return (readCR("0") & 0x80000000) == 0x80000000;
}

pub fn isPAEEnabled() bool {
    return (readCR("4") & (1 << 5)) == (1 << 5);
}

pub fn isPSEEnabled() bool {
    return (readCR("4") & 0x00000010) == 0x00000010;
}

pub fn isX87EmulationEnabled() bool {
    return (readCR("0") & 0b100) == 0b100;
}

pub fn isTSSSet() bool {
    return (readCR("0") & 0b1000) == 0b1000;
}

pub fn cpuid(leaf_id: u32, sub_id: u32) [4]u32 {
    var registers: [4]u32 = undefined;

    asm volatile (
        \\cpuid
        \\movl %%eax, 0(%[leaf_ptr])
        \\movl %%ebx, 4(%[leaf_ptr])
        \\movl %%ecx, 8(%[leaf_ptr])
        \\movl %%edx, 12(%[leaf_ptr])
        :
        : [leaf_id] "{eax}" (leaf_id),
          [subid] "{ecx}" (sub_id),
          [leaf_ptr] "r" (&registers)
        : "eax", "ebx", "ecx", "edx"
    );

    return registers;
}

pub fn readMSR(msr: u32) u64 {
    return asm volatile (
        \\rdmsr
        \\shl $32, %%rdx
        \\or %%rdx, %%rax
        \\mov %%rax, %[result]
        : [result] "=r" (-> u64)
        : [msr] "{rcx}" (msr)
    );
}

pub fn writeMSR(msr: u32, value: u64) void {
    asm volatile ("wrmsr"
        :
        : [msr] "{rcx}" (msr),
          [value] "{rax}" (value)
    );
}

pub fn invlpg(v_addr: usize) void {
    asm volatile ("invlpg (%[v_addr])"
        :
        : [v_addr] "r" (v_addr)
        : "memory"
    );
}

pub const EFER_MSR = 0xC0000080;
pub fn isLongModeEnabled() bool {
    // if (!hasCPUID()) return false; // FIXME(Ryan): use another method.
    var registers: [4]u32 = cpuid(0x80000000, 0);
    if (registers[0] < 0x80000001) return false;

    var eferMSR: u64 = readMSR(EFER_MSR);
    return (eferMSR & (1 << 10)) != 0 and (eferMSR & (1 << 8)) != 0; // EFER.LMA & EFER.LME.
}

pub const STAR_MSR = 0xC0000081;
pub fn enableSystemCallExtensions() void {
    serial.writeText("System call extensions will be enabled...\n");
    var buf: [4096]u8 = undefined;
    var eferMSR = readMSR(EFER_MSR);
    writeMSR(EFER_MSR, (eferMSR | 0x1)); // Enable SCE bit.
    var starMSR = readMSR(STAR_MSR);
    writeMSR(STAR_MSR, 0x00180008); // GDT segment.
    serial.writeText("System call extensions enabled.\n");
}

pub fn rdtsc() u64 {
    return asm volatile (
        \\rdtsc
        \\shl $32, %%rax
        \\or %%rcx, %%rax
        \\mov %%rax, %[val]
        : [val] "=m" (-> u64)
    );
}

pub fn ioWait() void {
    out(0x80, @as(u8, 0));
}

pub fn out(port: u16, data: anytype) void {
    switch (@TypeOf(data)) {
        u8 => asm volatile ("outb %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{al}" (data)
        ),
        u16 => asm volatile ("outw %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{ax}" (data)
        ),
        u32 => asm volatile ("outl %[data], %[port]"
            :
            : [port] "{dx}" (port),
              [data] "{eax}" (data)
        ),
        else => @compileError("Invalid data type for out. Only u8, u16 or u32, found: " ++ @typeName(@TypeOf(data))),
    }
}

pub fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type)
            : [port] "N{dx}" (port)
        ),
        else => @compileError("Invalid port type for in. Only u8, u16 or u32, found: " ++ @typeName(@TypeOf(port))),
    };
}

pub fn getClockInterval() u64 {
    return pit.time_ns;
}
