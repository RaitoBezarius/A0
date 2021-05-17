const serial = @import("../../debug/serial.zig");
const platform = @import("platform.zig");
const pmem = @import("pmem.zig");
const tty = @import("../../graphics/tty.zig");

const panic = tty.panic;

var buf: [128]u8 = undefined;

// (MAXPHYADDR is at most 52)

// Specification : IDM 3-4-30 (with MAXPHYADDR = 52).
// It would be best to have a different structure for each level
// of the page tables hierarchy, but since all the structures are
// compatible, we use only one declaration.
// This choice implies that two bits of the structure are somewhat
// ill-behaved (PAT and G), but the only consequence should be a
// slight cognitive overhead when using these bits. Fortunately,
// these bits should not be manipulated too often.
pub const PageTableEntry = packed struct {
    // True iff the entry is filled
    present: bool,
    // Read/Write : if 0, writes may not be allowed
    RW: bool,
    // User/Supervisor : if 0, user-mode accesses are not allowed
    US: bool,
    // Page-level Write Through (see note about PAT)
    PWT: bool,
    // Page-level Cache Disable (see note about PAT)
    PCD: bool,
    // Accessed : indicates wether software has accessed data referenced by this entry
    A: bool,
    // FOR 4KB PAGES : Dirty, indicates wether software has written data referenced
    // by this entry; otherwise ignored
    D: bool,
    // PAT and G : we need to regroup these two fields to avoid a compiler bug :/
    // For 4KB-pages, at the current state of the OS, this has no effect,
    // see the Intel developer's manual (vol.3-11-35).
    // See the Intel developer's manual (vol.3-4-29)
    // For pd's and pdpt's, the first bit indicates when we have a hugepage.
    merged: u2,
    // Ignored
    b11_8: u3,
    // The most significant bits of the physical address of the data referenced by
    // this entry
    phy_addr: u40,
    // Ignored
    b62_52: u11,
    // eXecute Disable (under certain circumstances, ibid.; otherwise reserved)
    XD: bool,

    pub fn zero() PageTableEntry {
        return PageTableEntry{
            .present = false,
            .RW = false,
            .US = false,
            .PWT = false,
            .PCD = false,
            .A = false,
            .D = false,
            .merged = 0,
            .b11_8 = 0,
            .phy_addr = 0,
            .b62_52 = 0,
            .XD = false,
        };
    }

    pub fn new(phy_addr: u64, allow_writes: bool, allow_user: bool) PageTableEntry {
        return PageTableEntry{
            .present = true,
            .RW = allow_writes,
            .US = allow_user,
            .PWT = false,
            .PCD = false,
            .A = false,
            .D = false,
            .merged = 0,
            .b11_8 = 0,
            .phy_addr = @truncate(u40, phy_addr >> 12),
            .b62_52 = 0,
            .XD = false,
        };
    }

    pub fn newHuge(phy_addr: u64, allow_writes: bool, allow_user: bool) PageTableEntry {
        return PageTableEntry{
            .present = true,
            .RW = allow_writes,
            .US = allow_user,
            .PWT = false,
            .PCD = false,
            .A = false,
            .D = false,
            .merged = 0b01,
            .b11_8 = 0,
            .phy_addr = @truncate(u40, phy_addr >> 12),
            .b62_52 = 0,
            .XD = false,
        };
    }

    pub fn isHugepage(self: PageTableEntry) bool {
        return self.merged & 0b1 != 0;
    }

    pub fn get_phy_addr(self: PageTableEntry) u64 {
        return self.phy_addr << 12;
    }

    pub fn set_phy_addr(self: PageTableEntry, physical: u64) void {
        self.phy_addr = @as(u40, physical >> 12);
    }

    pub fn get_1GB_phy_addr(self: PageTableEntry) u64 {
        return (self.phy_addr & ~@as(u40, 0b111111111111111111)) << 12;
    }

    pub fn get_2MB_phy_addr(self: PageTableEntry) u64 {
        return (self.phy_addr & ~@as(u40, 0b111111111)) << 12;
    }

    pub fn as_u64(self: *align(8) PageTableEntry) u64 {
        return @ptrCast(*u64, self).*;
    }

    pub fn debug(self: *PageTableEntry) void {
        serial.printf(buf[0..], ".present={}; .RW={}; .US={}; physical address = {x}\n", .{ self.present, self.RW, self.US, self.get_phy_addr() });
    }
};

pub const LinearAddress = packed struct {
    offset: u12,
    pt: u9,
    pd: u9,
    pdpt: u9,
    pml4: u9,
    pml5: u9,
    reserved: u7,

    pub fn as_u64(self: LinearAddress) u64 {
        return @bitCast(u64, self);
    }

    // This constructor ensures that the resulting linear address in _canonical_.
    // (See IDM 1-3-10, §3.3.7.1 -- non-canonical linear addreses trigger #GP,
    // see IDM 3-6-43 - "General Protection Exception in 64-bit Mode".)
    pub fn four_level_addr(pml4: u9, pdpt: u9, pd: u9, pt: u9, offset: u12) align(8) LinearAddress {
        const sign = pml4 & (1 << 8) != 0;
        const pml5: u9 = if (sign) 511 else 0;
        const reserved: u7 = if (sign) 127 else 0;
        return LinearAddress{
            .reserved = reserved,
            .pml5 = pml5,
            .pml4 = pml4,
            .pdpt = pdpt,
            .pd = pd,
            .pt = pt,
            .offset = offset,
        };
    }

    // Unsafe constructor, this one does _not_ ensure canonicity of the address.
    // (See the comment on `four_level_addr`.)
    pub fn from_u64(i: u64) align(8) LinearAddress {
        var addr = @bitCast(LinearAddress, i);
        return addr;
    }

    pub fn debug(self: *const LinearAddress) void {
        serial.printf(buf[0..], ".reserved={}; .pml5={}; .pml4={}; .pdpt={}; .pd={}; .pt={}; .offset={}\n", .{ self.reserved, self.pml5, self.pml4, self.pdpt, self.pd, self.pt, self.offset });
    }
};

pub fn findPhysicalAddress(linear: LinearAddress) ?u64 {
    const pml4 = @intToPtr(*[512]PageTableEntry, platform.readCR("3") & ~@as(u64, 0xFFF));

    if (!pml4[linear.pml4].present) {
        return null;
    }
    const pdpt = @intToPtr(*[512]PageTableEntry, pml4[linear.pml4].get_phy_addr());

    if (!pdpt[linear.pdpt].present) {
        return null;
    }

    if (pdpt[linear.pdpt].isHugepage()) {
        const phy_addr = pdpt[linear.pdpt].get_1GB_phy_addr() + (@intCast(u64, linear.pd) << 12) +
            (@intCast(u64, linear.pt) << 12) + @intCast(u64, linear.offset);

        return phy_addr;
    } else {
        const pd = @intToPtr(*[512]PageTableEntry, pdpt[linear.pdpt].get_phy_addr());

        if (!pd[linear.pd].present) {
            return null;
        }

        if (pd[linear.pd].isHugepage()) {
            const phy_addr = pd[linear.pd].get_2MB_phy_addr() + (@intCast(u64, linear.pt) << 12) + @intCast(u64, linear.offset);
            return phy_addr;
        } else {
            const pt = @intToPtr(*[512]PageTableEntry, pd[linear.pd].get_phy_addr());

            if (!pt[linear.pt].present) {
                return null;
            }

            const physical = pt[linear.pt].get_phy_addr() + @intCast(u64, linear.offset);
            return physical;
        }
    }
}

fn acquireSubtable(entry: *PageTableEntry) *[512]PageTableEntry {
    if (entry.present) {
        if (entry.isHugepage()) {
            panic("Tried to remap inside a hugepage !", .{});
        }

        const legacy_table = @intToPtr(*[512]PageTableEntry, entry.get_phy_addr());

        if (pmem.isOurs(entry.get_phy_addr())) {
            return legacy_table;
        } else {
            var table = @intToPtr(*[512]PageTableEntry, pmem.allocatePage());

            var i: u64 = 0;
            while (i < 512) : (i += 1) {
                table[i] = legacy_table[i];
            }

            entry.* = PageTableEntry.new(@ptrToInt(table), true, false);
            return table;
        }
    } else {
        var table = @intToPtr(*[512]PageTableEntry, pmem.allocatePage());

        var i: u64 = 0;
        while (i < 512) : (i += 1) {
            table[i] = PageTableEntry.zero();
        }

        entry.* = PageTableEntry.new(@ptrToInt(table), true, false);
        return table;
    }
}

pub fn unmap(linear: LinearAddress) void {
    // The only caveat is that we have to make `invlpg` calls before exitting
    // this function, as we are touching the virtual memory structure.
    // See IDM 2-3-520 for invlpg;
    // See IDM 3-4-39 and 3-4-40, §§4.10.2.1 4.10.2.2 : each entry in a TLB
    //   is referenced by a _page number_, i.e. the upper bits of a linear address.
    // See IDM 3-4-45, §4.10.4.1 about when to invalidate TLBs.
    // See IDM 3-11-1 for TLBs in general and caching.
    const pml4 = @intToPtr(*[512]PageTableEntry, platform.readCR("3") & ~@as(u64, 0xFFF));
    const pml4_entry = &pml4[linear.pml4];

    if (!pml4_entry.present) {
        platform.invlpg(linear.as_u64());
        return;
    }

    const pdpt: *[512]PageTableEntry = acquireSubtable(pml4_entry);
    const pdpt_entry = &pdpt[linear.pdpt];

    if (!pdpt_entry.present) {
        platform.invlpg(linear.as_u64());
        return;
    }

    const pd: *[512]PageTableEntry = acquireSubtable(pdpt_entry);
    const pd_entry = &pd[linear.pd];

    if (!pd_entry.present) {
        platform.invlpg(linear.as_u64());
        return;
    }

    const pt: *[512]PageTableEntry = acquireSubtable(pd_entry);
    const pt_entry = &pt[linear.pt];

    if (!pt_entry.present) {
        platform.invlpg(linear.as_u64());
        return;
    }

    pt[linear.pt] = PageTableEntry.zero();
    platform.invlpg(linear.as_u64());
}

// Maps a 4kb page
// 2Mb pages are also mappable, see below.
pub fn map(linear: LinearAddress, physical: u64) void {
    const pml4 = @intToPtr(*[512]PageTableEntry, platform.readCR("3") & ~@as(u64, 0xFFF));
    var pdpt: *[512]PageTableEntry = acquireSubtable(&pml4[linear.pml4]);
    var pd: *[512]PageTableEntry = acquireSubtable(&pdpt[linear.pdpt]);
    var pt: *[512]PageTableEntry = acquireSubtable(&pd[linear.pd]);

    if (pt[linear.pt].present) {
        panic("Tried to map an already mapped address.", .{});
    }

    pt[linear.pt] = PageTableEntry.new(physical, true, false);
    pd[linear.pd] = PageTableEntry.new(@ptrToInt(pt), true, false);
    pdpt[linear.pdpt] = PageTableEntry.new(@ptrToInt(pd), true, false);
    pml4[linear.pml4] = PageTableEntry.new(@ptrToInt(pdpt), true, false);

    // Don't forget to invalidate !
    platform.invlpg(linear.as_u64());
}

pub fn map2MB(linear: LinearAddress, physical: u64) void {
    const pml4 = @intToPtr(*[512]PageTableEntry, platform.readCR("3") & ~@as(u64, 0xFFF));
    var pdpt: *[512]PageTableEntry = acquireSubtable(&pml4[linear.pml4]);
    var pd: *[512]PageTableEntry = acquireSubtable(&pdpt[linear.pdpt]);

    if (pd[linear.pd].present) {
        panic("Tried to map an already mapped address.", .{});
    }

    pd[linear.pd] = PageTableEntry.newHuge(physical, true, false);
    pdpt[linear.pdpt] = PageTableEntry.new(@ptrToInt(pd), true, false);
    pml4[linear.pml4] = PageTableEntry.new(@ptrToInt(pdpt), true, false);

    // Don't forget to invalidate !
    platform.invlpg(linear.as_u64());
}

pub fn initialize() void {
    // Gain control over memory protection.
    // We need to copy the legacy pml4, because we aren't allowed to write to it.
    // This function just changes the frame where `CR3` points.

    // For memory : see Intel Developer's Manual, vol.3-4-30

    // To check 5-level memory : check CR4.LA57
    //  * CR0.PG = 1 (bit 31)
    //  * CR4.PAE = 1 (bit 5)
    //  * IA32_EFER.LME = 1
    //  * CR4.LA57 = 1 (bit 12)
    //  (For CR0..CR4 : see IDM 3-2-13)
    //  (For IA32_EFER : see IDM 3-2-9)
    //
    //  UEFI guarantees that we already in IA-32e, x64 submode.
    //  (See UEFI spec, p.27 - 2.3.4)
    //  We just check that we are only using 4-level paging.
    var cr4_la57 = platform.readCR("4") & (1 << 12) != 0;
    if (cr4_la57) {
        panic("Unexpected 5-level paging at UEFI handoff.", .{});
    } else {
        serial.writeText("4-level paging, as expected.\n");
    }

    var old_pml4 = @intToPtr(*[512]PageTableEntry, platform.readCR("3") & ~@intCast(u64, 0xFFF));
    var pml4: *[512]PageTableEntry = @intToPtr(*[512]PageTableEntry, pmem.allocatePage());

    // Copy the old pml4
    var i: u64 = 0;
    while (i < 512) : (i += 1) {
        pml4[i] = old_pml4[i];
    }

    // Rewrite CR3
    platform.writeCR("3", (platform.readCR("3") & 0xFFF) | @ptrToInt(pml4));

    serial.writeText("We now have control over the virtual memory !\n");
}
