pub fn initialize() void {}

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

// Read CR2
pub inline fn readCR2() usize {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> usize)
    );
}

// Write CR3
pub inline fn writeCR3(pd: usize) void {
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (pd)
    );
}

// Read byte from a port
pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8)
        : [port] "N{dx}" (port)
    );
}

// Write byte on a port
pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port)
    );
}
