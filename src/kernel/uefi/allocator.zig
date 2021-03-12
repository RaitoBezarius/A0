const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const uefi = std.os.uefi;

const Allocator = std.mem.Allocator;
const ThisAllocator = @This();

// Pre-boot allocator in UEFI environment
var systemAllocatorState = Allocator{
    .allocFn = alloc,
    .resizeFn = resize,
};

pub const systemAllocator = &systemAllocatorState;

const ALLOCATION_HEADER_COOKIE = 0x3b064be8fe2dc;
const AllocationHeader = struct {
    cookie: u64, size: usize, base: [*]align(8) u8
};

// This function assumes that we have not exited boot services, otherwise KVM internal error or UEFI system reset will kick in.
fn alloc(allocator: *Allocator, n: usize, ptrAlign: u29, lenAlign: u29, ra: usize) error{OutOfMemory}![]u8 {
    assert(n > 0);

    const bootServices = uefi.system_table.boot_services.?;
    const MemoryType = uefi.tables.MemoryType;
    const Success = uefi.Status.Success;

    var ptr: [*]align(8) u8 = undefined;
    const adjustedSize = n + ptrAlign + @sizeOf(AllocationHeader);
    const result = bootServices.allocatePool(MemoryType.LoaderData, adjustedSize, &ptr);
    if (result != Success) {
        return error.OutOfMemory;
    }

    const adjustedPtr = std.mem.alignForward(@ptrToInt(ptr) + @sizeOf(AllocationHeader), ptrAlign);
    const allocHeaderPtr = @intToPtr(*AllocationHeader, adjustedPtr - @sizeOf(AllocationHeader));

    allocHeaderPtr.cookie = ALLOCATION_HEADER_COOKIE;
    allocHeaderPtr.base = ptr;
    allocHeaderPtr.size = adjustedSize;

    return @intToPtr([*]u8, adjustedPtr)[0..n];
}

fn resize(
    allocator: *Allocator,
    buf: []u8,
    bufAlign: u29,
    newSize: usize,
    lenAlign: u29,
    returnAddress: usize,
) Allocator.Error!usize {
    // TODO: implement resizing.
    if (newSize != 0) {
        return error.OutOfMemory;
    }

    const allocHeaderPtr = @intToPtr(*AllocationHeader, @ptrToInt(buf.ptr) - @sizeOf(AllocationHeader));

    if (allocHeaderPtr.cookie != ALLOCATION_HEADER_COOKIE) {
        // This is the sign of memory stomping.
        return error.OutOfMemory;
    }

    const freedSize = allocHaederPtr.size;
    _ = uefi.system_table.boot_services.?.freePool(allocHeaderPtr.base);

    return freedSize;
}
