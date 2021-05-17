
const std = @import("std");
const vmem = @import("vmem.zig");
const pmem = @import("pmem.zig");
const serial = @import("../../debug/serial.zig");

const Allocator = std.mem.Allocator;
const LinearAddress = vmem.LinearAddress;

// Each time we allocate, we add the length of the
// allocated memory to this.
// This means wasting linear address space, but since
// we got so much of it compared to the quantity we actually
// require, we can affort to do that.
var currentHeapBase : u64 = undefined;

const ALLOC_DICT_LENGTH = 2048;
const AllocInfo = struct {
    base : u64,
    len : u64
};
var allocDict : [4096]AllocInfo = undefined;

pub var kernelAllocator = Allocator {
    .allocFn = alloc,
    .resizeFn = resize,
};

fn alloc(
    allocator : *Allocator,
    len : usize,
    ptrAlign : u29,
    lenAlign : u29,
    retAddr : usize
) error{OutOfMemory}![]u8 {
    if (ptrAlign > 4096) {
        return error.OutOfMemory;
    }

    var tgtLen : u64 = 0;
    if (lenAlign == 0) {
        tgtLen = len;
    } else {
        tgtLen = (len/lenAlign) * lenAlign;
    }
    if (tgtLen < len) { tgtLen += lenAlign; }
    // Transform tgtLen to a number of pages
    if (@rem(tgtLen, 4096) != 0) {
        tgtLen = (tgtLen / 4096) + 1;
    } else {
        tgtLen = tgtLen / 4096;
    }

    var i : u64 = 0;
    while (i < ALLOC_DICT_LENGTH) : (i += 1) {
        if (allocDict[i].base == 0) {
            allocDict[i] = AllocInfo { .base = currentHeapBase, .len = tgtLen };
        }
    }

    const base = currentHeapBase;
    i = 0;
    while (i < tgtLen) : (i += 1) {
        vmem.map(LinearAddress.from_u64(currentHeapBase), pmem.allocatePage());
        currentHeapBase += 4096;
    }

    return @intToPtr([*]u8, base)[0..len];
}

fn resize (
    allocator : *Allocator,
    buf : []u8,
    bufAlign : u29,
    newLen : usize,
    lenAlign : u29,
    returnAddress : usize
) Allocator.Error!usize {
    const addr : u64 = 0;

    var i : u64 = 0;
    var info : *AllocInfo = undefined;
    while (i < ALLOC_DICT_LENGTH) : (i += 1) {
        if (allocDict[i].base == @ptrToInt(buf.ptr)) {
            info = &allocDict[i];
        }
    }

    if (409*info.len < newLen) {
        return error.OutOfMemory;
    }

    var newPagesLen : u64 = 0;
    if (@rem(newLen, 4096) == 0) {
        newPagesLen = newLen/4096;
    } else {
        newPagesLen = newLen/4096+1;
    }

    i = newPagesLen;
    while (i < info.len) : (i += 1) {
        vmem.unmap(LinearAddress.from_u64(info.base + 4096*i));
    }

    if (newLen == 0) {
        info.* = AllocInfo { .base = 0, .len = 0 };
    } else {
        info.le = newLen;
    }

    return info.len - newPagesLen;
}

pub fn initialize(base : LinearAddress) void {
    currentHeapBase = base.as_u64();
    var i : u64 = 0;
    while (i < 2*ALLOC_DICT_LENGTH) : (i += 1) {
        allocDict[i] = AllocInfo { .base = 0, .len = 0 };
    }
}

