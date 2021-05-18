const layout = @import("layout.zig");
const tty = @import("../../lib/graphics/tty.zig");
const kernelGraphics = @import("../../uefi/graphics.zig");
const panic = kernelGraphics.panic;

var mem_base: u64 = undefined;
var available: [layout.REQUIRED_PAGES_COUNT]bool = init: {
    var val: [layout.REQUIRED_PAGES_COUNT]bool = undefined;
    for (val) |*pt| {
        pt.* = true;
    }
    break :init val;
};

// Register the base address of a location where
// REQUIRED_PAGES_COUNT consecutive pages are available.
pub fn registerAvailableMem(base: u64) void {
    mem_base = base;
}

pub fn isOurs(addr: u64) bool {
    if (addr < mem_base) {
        return false;
    }
    const i = (addr - mem_base) >> 12;
    return 0 <= i and i < layout.REQUIRED_PAGES_COUNT;
}

pub fn allocatePage() u64 {
    var i: u64 = 0;
    while (i < layout.REQUIRED_PAGES_COUNT) : (i += 1) {
        if (available[i]) {
            available[i] = false;
            return mem_base + i * 0x1000;
        }
    }
    panic("No pages of memory left (in pmem.zig).\n", .{});
}

pub fn freePage(addr: u64) void {
    if (is_ours(addr)) {
        available[i] = true;
    } else {
        panic("Tried to free a page that doesn't belong to us !\n", .{});
    }
}
