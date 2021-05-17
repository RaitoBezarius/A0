
const std = @import("std");
const vmem = @import("vmem.zig");
const pmem = @import("pmem.zig");

const Allocator = std.mem.Allocator;
const LinearAddress = vmem.LinearAddress;

// Each time we allocate, we add the length of the
// allocated memory to this.
// This means wasting linear address space, but since
// we got so much of it compared to the quantity we actually
// require, we can affort to do that.
var currentHeapBase : u64 = undefined;
var allocDict : [4096]u64 = undefined;

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
    
    var tgtLen = (len/lenAlign) * lenAlign;
    if (tgtLen < len) { tgtLen += lenAlign; }
    // Transform tgtLen to a number of pages
    if (@rem(tgtLen, lenAlign) != 0) {
        tgtLen = (tgtLen / 4096) + 4096;
    } else {
        tgtLen = tgtLen / 4096;
    }

    const base = currentHeapBase;
    var i : u64 = 0;
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
    //const addr : u64 = 0;

    //var i : u64 = 0;
    //for (i < 2048) : (i += 1) {
    //    if (allocDict[2*i] == @ptrToInt(buf)) {
    //        i = allocDict[2*i + 1];
    //    }
    //}

    //return error.OutOfMemory;
    return 0;
}

pub fn initialize(base : LinearAddress) void {
    currentHeapBase = base.as_u64();
}

