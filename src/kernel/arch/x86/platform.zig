pub extern fn getEflags() u32;
pub extern fn getCS() u32;

pub fn initialize() void {
    // gdt.initialize();
    // idt.initialize();

    // pic.initialize();
    // isr.initialize();
    // irq.initialize();

    // TODO: init paging

    // pit.initialize();
    // rtc.initialize();
}

pub inline fn hlt() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn hang() noreturn {
    cli();
    hlt();
}

// Load a new IDT
pub inline fn lidt(idtr: usize) void {
    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "r" (idtr)
    );
}

// Load a new Task Register
pub inline fn ltr(desc: u16) void {
    asm volatile ("ltr %[desc]"
        :
        : [desc] "r" (desc)
    );
}

// Invalidate TLB entry associated with given vaddr
pub inline fn invlpg(v_addr: usize) void {
    asm volatile ("invlpg (%[v_addr])"
        :
        : [v_addr] "r" (v_addr)
        : "memory"
    );
}

pub inline fn readCR(comptime number: []const u8) usize {
    return asm volatile ("mov %%cr" ++ number ++ ", %[ret]"
        : [ret] "=r" (-> usize)
    );
}

pub inline fn writeCR(comptime number: []const u8, value: usize) void {
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
        \\mov %[result], %%rdx
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

pub const EFER_MSR = 0xC0000080;
pub fn isLongModeEnabled() bool {
    // if (!hasCPUID()) return false; // FIXME(Ryan): use another method.
    var registers: [4]u32 = cpuid(0x80000000, 0);
    if (registers[0] < 0x80000001) return false;

    registers = cpuid(0x80000001, 0);
    var eferMSR: u64 = readMSR(EFER_MSR);

    return (registers[3] & (1 << 29)) == (1 << 29) and (eferMSR & (1 << 10)) == (1 << 10);
}

pub fn enableSystemCallExtensions() void {
    var eferMSR = readMSR(EFER_MSR);
    writeMSR(EFER_MSR, eferMSR & 0x1); // Enable SCE bit.
    var starMSR = readMSR(STAR_MSR);
    writeMSR(STAR_MSR, 0x00180008); // GDT segment.
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

pub inline fn ioWait() void {
    out(0x80, @as(u8, 0));
}

pub inline fn out(port: u16, data: anytype) void {
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

pub inline fn in(comptime Type: type, port: u16) Type {
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
