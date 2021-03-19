const utils = @import("utils.zig");
const x86 = @import("x86.zig");
const pmem = @import("pmem.zig");
const layout = @import("layout.zig");
const assert = @import("std").debug.assert;

const PageEntry = usize;

const PageMapLevel5 = @intToPtr([*]PageEntry, layout.PageMapLevel5);
const PageMapLevel4 = @intToPtr([*]PageEntry, layout.PageMapLevel4);
const PageDirectoryPointer = @intToPtr([*]PageEntry, layout.PageDirectoryPointer);
const PageDirectory = @intToPtr([*]PageEntry, layout.PageDirectory);
const PageTables = @intToPtr([*]PageEntry, layout.PageTables);

pub const PAGE_PRESENT = (1 << 0);
pub const PAGE_WRITE = (1 << 1);
pub const PAGE_USER = (1 << 2);
pub const PAGE_4MB = (1 << 7);
pub const PAGE_GLOBAL = (1 << 8);
pub const PAGE_ALLOCATED = (1 << 9);

fn pdIndex(vaddr: usize) usize {
    return v_addr >> 22;
}
fn ptIndex(vaddr: usize) usize {
    return (vaddr >> 12) & 0x3FF;
}

fn pdEntry(vaddr: usize) *PageEntry {
    return &PageDirectory[pdIndex(vaddr)];
}
fn ptEntry(vaddr: usize) *PageEntry {
    return &PageTables[(pdIndex(vaddr) * 0x400) + ptIndex(vaddr)];
}

pub fn virtualToPhysical(vaddr: usize) ?usize {
    const pd_entry = pdEntry(vaddr);
    if (pd_entry.* == 0) return null;
    const pt_entry = ptEntry(vaddr);

    return x86.pageBase(pt_entry.*);
}

pub fn map(vaddr: usize, paddr: ?usize, flags: u32) void {
    assert(vaddr >= layout.Identity);

    const pd_entry = pdEntry(vaddr);
    const pt_entry = ptEntry(vaddr);

    if (pd_entry.* == 0) {
        pd_entry.* = pmem.allocate() | flags | PAGE_PRESENT | PAGE_WRITE | PAGE_USER;
        invlpg(@ptrToInt(pt_entry));

        const pt = @ptrCast([*]PageEntry, x86.pageBase(pt_entry));
        zeroPageTable(pt);
    }

    if (paddr) |p| {
        if (pt_entry.* & PAGE_ALLOCATED != 0) pmem.free(pt_entry.*);

        pt_entry.* = x86.pageBase(p) | flags | PAGE_PRESENT;
    } else {
        if (pt_entry.* & PAGE_ALLOCATED != 0) {
            pt_entry.* = x86.pageBase(pt_entry.*) | flags | PAGE_PRESENT | PAGE_ALLOCATED;
        } else {
            pt_entry.* = pmem.allocate() | flags | PAGE_PRESENT | PAGE_ALLOCATED;
        }
    }

    invlpg(vaddr);
}

pub fn unmap(vaddr: usize) void {
    assert(vaddr >= layout.Identity);

    const pd_entry = pdEntry(vaddr);
    if (pd_entry.* == 0) return;

    const pt_entry = ptEntry(vaddr);

    if (pt_entry.* & PAGE_ALLOCATED != 0) pmem.free(pt_entry.*);

    pt_entry.* = 0;
    invlpg(vaddr);
}

pub fn mapZone(vaddr: usize, paddr: ?usize, size: usize, flags: u32) void {
    var i: usize = 0;
    while (i < size) : (i += x86.PAGE_SIZE) {
        map(vaddr + i, if (p_addr) |p| p + i else null, flags);
    }
}

pub fn unmapZone(vaddr: usize, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += x86.PAGE_SIZE) {
        unmap(vaddr + i);
    }
}

fn zeroPageTable(page_table: [*]PageEntry) void {
    const pt = @ptrCast([*]u8, page_table);
    @memset(pt, 0, x86.PAGE_SIZE);
}

// Invalidate TLB entry associated with given vaddr
pub inline fn invlpg(v_addr: usize) void {
    asm volatile ("invlpg (%[v_addr])"
        :
        : [v_addr] "r" (v_addr)
        : "memory"
    );
}

extern fn setupPaging(pd: usize) void;
pub fn initialize() void {
    // TODO: signal start of paging setup.
    assert(pmem.stack_end < layout.Identity);

    const pd = @intToPtr([*]PageEntry, pmem.allocate()); // Page directory's page.
    zeroPageTable(pd);

    // Identity mapping of the kernel (first 8MB) and make the PD loop on the last entry.
    pd[0] = 0x000000 | PAGE_PRESENT | PAGE_WRITE | PAGE_4MB | PAGE_GLOBAL;
    pd[1] = 0x400000 | PAGE_PRESENT | PAGE_WRITE | PAGE_4MB | PAGE_GLOBAL;
    pd[1023] = @ptrToInt(pd) | PAGE_PRESENT | PAGE_WRITE;

    // TODO: register an interruption for page fault handler
    setupPaging(@ptrToInt(pd));
    // TODO: actually perform a real setup, loadPML5(@ptrToInt(PML5));

    // TODO: signal end of paging setup.
}
