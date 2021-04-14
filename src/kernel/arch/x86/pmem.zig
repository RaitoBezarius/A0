const std = @import("std");
const platform = @import("platform.zig");
const x86 = @import("x86.zig");

const uefi = std.os.uefi;
const MemoryType = uefi.tables.MemoryType;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;

const layout = @import("layout.zig");
// TODO: find out a better way to make this.
const uefiMemory = @import("../../uefi/memory.zig");
const serial = @import("../../debug/serial.zig");
const fmt = @import("std").fmt;

var currentAllocator: *std.mem.Allocator = undefined;

pub fn available() usize {}

pub fn allocate() usize {
    return @ptrToInt(@ptrCast(*u8, currentAllocator.alloc(u8, x86.PAGE_SIZE) catch unreachable));
}

pub fn free(address: usize) void {
    currentAllocator.free(@intToPtr([*]u8, address).*);
}

pub fn initialize(preUEFIAllocator: *std.mem.Allocator) void {
    serial.writeText("Physical memory initializing...\n");
    currentAllocator = preUEFIAllocator;
    serial.writeText("Initialized with pre-UEFI allocator.\n");
}

// Use the memory map to reclaim all memory and reorganize it.
pub fn overthrowUEFI() void {}
