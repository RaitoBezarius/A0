const idt = @import("idt.zig");

// Interrupt Service Routines defined externally in assembly.
extern fn isr0() void;
extern fn isr1() void;
extern fn isr2() void;
extern fn isr3() void;
extern fn isr4() void;
extern fn isr5() void;
extern fn isr6() void;
extern fn isr7() void;
extern fn isr8() void;
extern fn isr9() void;
extern fn isr10() void;
extern fn isr11() void;
extern fn isr12() void;
extern fn isr13() void;
extern fn isr14() void;
extern fn isr15() void;
extern fn isr16() void;
extern fn isr17() void;
extern fn isr18() void;
extern fn isr19() void;
extern fn isr20() void;
extern fn isr21() void;
extern fn isr22() void;
extern fn isr23() void;
extern fn isr24() void;
extern fn isr25() void;
extern fn isr26() void;
extern fn isr27() void;
extern fn isr28() void;
extern fn isr29() void;
extern fn isr30() void;
extern fn isr31() void;
extern fn isr32() void;
extern fn isr33() void;
extern fn isr34() void;
extern fn isr35() void;
extern fn isr36() void;
extern fn isr37() void;
extern fn isr38() void;
extern fn isr39() void;
extern fn isr40() void;
extern fn isr41() void;
extern fn isr42() void;
extern fn isr43() void;
extern fn isr44() void;
extern fn isr45() void;
extern fn isr46() void;
extern fn isr47() void;
extern fn isr128() void;

////
// Install the Interrupt Service Routines in the IDT.
//
pub fn install_exceptions() void {
    // Exceptions.
    idt.setGate(0, idt.InterruptGateFlags, isr0);
    idt.setGate(1, idt.InterruptGateFlags, isr1);
    idt.setGate(2, idt.InterruptGateFlags, isr2);
    idt.setGate(3, idt.InterruptGateFlags, isr3);
    idt.setGate(4, idt.InterruptGateFlags, isr4);
    idt.setGate(5, idt.InterruptGateFlags, isr5);
    idt.setGate(6, idt.InterruptGateFlags, isr6);
    idt.setGate(7, idt.InterruptGateFlags, isr7);
    idt.setGate(8, idt.InterruptGateFlags, isr8);
    idt.setGate(9, idt.InterruptGateFlags, isr9);
    idt.setGate(10, idt.InterruptGateFlags, isr10);
    idt.setGate(11, idt.InterruptGateFlags, isr11);
    idt.setGate(12, idt.InterruptGateFlags, isr12);
    idt.setGate(13, idt.InterruptGateFlags, isr13);
    idt.setGate(14, idt.InterruptGateFlags, isr14);
    idt.setGate(15, idt.InterruptGateFlags, isr15);
    idt.setGate(16, idt.InterruptGateFlags, isr16);
    idt.setGate(17, idt.InterruptGateFlags, isr17);
    idt.setGate(18, idt.InterruptGateFlags, isr18);
    idt.setGate(19, idt.InterruptGateFlags, isr19);
    idt.setGate(20, idt.InterruptGateFlags, isr20);
    idt.setGate(21, idt.InterruptGateFlags, isr21);
    idt.setGate(22, idt.InterruptGateFlags, isr22);
    idt.setGate(23, idt.InterruptGateFlags, isr23);
    idt.setGate(24, idt.InterruptGateFlags, isr24);
    idt.setGate(25, idt.InterruptGateFlags, isr25);
    idt.setGate(26, idt.InterruptGateFlags, isr26);
    idt.setGate(27, idt.InterruptGateFlags, isr27);
    idt.setGate(28, idt.InterruptGateFlags, isr28);
    idt.setGate(29, idt.InterruptGateFlags, isr29);
    idt.setGate(30, idt.InterruptGateFlags, isr30);
    idt.setGate(31, idt.InterruptGateFlags, isr31);
}

// IRQs.
pub fn install_irqs() void {
    idt.setGate(32, idt.InterruptGateFlags, isr32);
    idt.setGate(33, idt.InterruptGateFlags, isr33);
    idt.setGate(34, idt.InterruptGateFlags, isr34);
    idt.setGate(35, idt.InterruptGateFlags, isr35);
    idt.setGate(36, idt.InterruptGateFlags, isr36);
    idt.setGate(37, idt.InterruptGateFlags, isr37);
    idt.setGate(38, idt.InterruptGateFlags, isr38);
    idt.setGate(39, idt.InterruptGateFlags, isr39);
    idt.setGate(40, idt.InterruptGateFlags, isr40);
    idt.setGate(41, idt.InterruptGateFlags, isr41);
    idt.setGate(42, idt.InterruptGateFlags, isr42);
    idt.setGate(43, idt.InterruptGateFlags, isr43);
    idt.setGate(44, idt.InterruptGateFlags, isr44);
    idt.setGate(45, idt.InterruptGateFlags, isr45);
    idt.setGate(46, idt.InterruptGateFlags, isr46);
    idt.setGate(47, idt.InterruptGateFlags, isr47);
}

// Syscalls.
pub fn install_syscalls() void {
    idt.setGate(128, idt.SYSCALL_GATE, isr128);
}
