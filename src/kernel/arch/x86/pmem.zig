
const serial = @import("../../debug/serial.zig");

const panic = serial.panic;

var mem_base: u64 = undefined;
var available: [64]bool = init: {
    var val: [64]bool = undefined;
    for (val) |*pt| {
        pt.* = true;
    }
    break :init val;
};

// Register the base address of a location where
// 64 consecutive pages are available.
pub fn registerAvailableMem(base: u64) void {
    mem_base = base;
}

pub fn is_ours(addr: u64) bool {
    if (addr < mem_base) { return false; }
    const i = (addr - mem_base) >> 12;
    return 0 <= i and i < 64;
}

pub fn allocatePage() u64 {
    var i: u64 = 0;
    while (i < 64) : (i += 1) {
        if (available[i]) {
            available[i] = false;
            return mem_base + i * 0x1000;
        }
    }
    panic("No pages of memory left (in pmem.zig).\n", null);
}

pub fn freePage(addr: u64) void {
    if (is_ours(addr)) {
        available[i] = true;
    } else {
        panic("Tried to free a page that doesn't belong to us !\n", null);
    }
}

