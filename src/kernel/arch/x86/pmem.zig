const platform = @import("platform.zig");
const x86 = @import("x86.zig");
const uefi = @import("std").os.uefi;
const MemoryType = uefi.tables.MemoryType;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;
const layout = @import("layout.zig");
// TODO: find out a better way to make this.
const uefiMemory = @import("../../uefi/memory.zig");
const serial = @import("../../debug/serial.zig");
const fmt = @import("std").fmt;
var stack: [*]usize = undefined; // Stack of free physical page
var stack_index: usize = 0;

pub var stack_size: usize = undefined;
pub var stack_end: usize = undefined;

fn panic(msg: []const u8) noreturn {
    serial.writeText("******** KERNEL PANIC:\n");
    serial.writeText(msg);
    serial.writeText("\n");
    platform.hang();
}

pub fn available() usize {
    return stack_index * x86.PAGE_SIZE;
}

pub fn allocate() usize {
    if (available() == 0) {
        panic("out of memory");
    }

    stack_index -= 1;
    return stack[stack_index];
}

pub fn free(address: usize) void {
    stack[stack_index] = x86.pageBase(address);
    stack_index += 1;
}

fn chillestChunk(memory_map: *uefiMemory.MemoryMap) MemoryDescriptor {
    var i: usize = 0;
    var min_nb_pages: usize = 160; // min 160 pages to have 640kb.
    var buf: [2048]u8 = undefined;

    while (i < memory_map.size) : (i += 1) {
        if ((memory_map.map[i].type == MemoryType.BootServicesCode or memory_map.map[i].type == MemoryType.BootServicesData) and memory_map.map[i].number_of_pages >= min_nb_pages) {
            serial.writeText(fmt.bufPrint(buf[0..], "Physical start: {x}, Nb pages: {d}\n", .{ memory_map.map[i].physical_start, memory_map.map[i].number_of_pages }) catch unreachable);
            return memory_map.map[i];
        }
    }

    panic("no chill chunk");
}

pub fn initialize() void {
    serial.writeText("Physical memory initializing...\n");
    serial.writeText("Kernel stack initializing...\n");

    const chillDescriptor = chillestChunk(uefiMemory.memoryMap);
    var buf: [1024]u8 = undefined;
    serial.writeText(fmt.bufPrint(buf[0..], "A chill chunk obtained: {d} pages.\n", .{chillDescriptor.number_of_pages}) catch unreachable);
    stack = @intToPtr([*]usize, chillDescriptor.physical_start);
    stack_size = chillDescriptor.number_of_pages * x86.PAGE_SIZE;
    stack_end = chillDescriptor.physical_start + stack_size;
    serial.writeText(fmt.bufPrint(buf[0..], "Kernel stack initialized, stack start: {x}, stack end: {x}.\n", .{ @ptrToInt(stack), stack_end }) catch unreachable);

    // Mark all pages as available.
    var i: usize = 0;
    while (i < uefiMemory.memoryMap.size) : (i += 1) {
        if (uefiMemory.memoryMap.map[i].type == MemoryType.ConventionalMemory) {
            var start = uefiMemory.memoryMap.map[i].physical_start;
            var end = start + (uefiMemory.memoryMap.map[i].number_of_pages * x86.PAGE_SIZE);

            start = if (start >= stack_end) start else stack_end;

            while (start < end) : (start += x86.PAGE_SIZE) {
                free(start);
            }
        }
    }

    serial.writeText(fmt.bufPrint(buf[0..], "Physical memory initialized, available: {d} MB.\n", .{available() / (1024 * 1024)}) catch unreachable);
}
