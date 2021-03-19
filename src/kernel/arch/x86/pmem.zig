const x86 = @import("x86.zig");
const uefi = @import("std").os.uefi;
const MemoryType = uefi.tables.MemoryType;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;
// TODO: find out a better way to make this.
const uefiMemory = @import("../../uefi/memory.zig");
var stack: [*]usize = undefined; // Stack of free physical page
var stack_index: usize = 0;

pub var stack_size: usize = undefined;
pub var stack_end: usize = undefined;

pub fn available() usize {
    return stack_index * x86.PAGE_SIZE;
}

pub fn allocate() usize {
    if (available() == 0) {
        //TODO: panic("out of memory");
    }

    stack_index -= 1;
    return stack[stack_index];
}

pub fn free(address: usize) void {
    stack[stack_index] = x86.pageBase(address);
    stack_index += 1;
}

fn biggestContinuousChunk(memory_map: *uefiMemory.MemoryMap) *MemoryDescriptor {
    var i: usize = 0;
    var best_desc: MemoryDescriptor = undefined;
    var best_nb_pages: usize = 0;

    while (i < memory_map.size) : (i += 1) {
        if (memory_map.map[i].type == MemoryType.ConventionalMemory and memory_map.map[i].number_of_pages >= best_nb_pages) {
            best_desc = memory_map.map[i];
            best_nb_pages = best_desc.number_of_pages;
        }
    }

    return &best_desc;
}

pub fn initialize() void {
    // TODO: write we are preparing for a kernel stack

    // Grab the biggest page first.
    // TODO: once we have the biggest page, finish temporary setup.
    // then, make it possible to use all the pages directly.
    const biggestDescriptor = biggestContinuousChunk(uefiMemory.memoryMap);
    stack = @intToPtr([*]usize, x86.pageAlign(@as(usize, biggestDescriptor.physical_start)));
    stack_size = biggestDescriptor.number_of_pages * x86.PAGE_SIZE;
    stack_end = x86.pageAlign(@ptrToInt(stack) + stack_size);
}
