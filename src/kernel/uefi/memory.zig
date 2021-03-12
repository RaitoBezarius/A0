const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const uefi = std.os.uefi;

const MemorySystemInfo = struct {
    totalAvailableMemory: usize = undefined
};
var memorySystemInfoState = MemorySystemInfo{};
pub const memorySystemInfo = &memorySystemInfoState;

const MemoryMap = struct {
    map: [*]uefi.tables.MemoryDescriptor = undefined,
    size: usize = 0,
    key: usize = undefined,
    descriptorSize: usize = undefined,
    descriptorVersion: u32 = undefined,

    pub fn refresh(self: *MemoryMap) void {
        const bootServices = uefi.system_table.boot_services.?;
        const MemoryType = uefi.tables.MemoryType;

        if (self.size > 0) {
            _ = bootServices.freePool(@ptrCast([*]align(8) u8, &self.map));
            self.size = 0;
        }

        const BufferTooSmall = uefi.Status.BufferTooSmall;
        while (bootServices.getMemoryMap(&self.size, self.map, &self.key, &self.descriptorSize, &self.descriptorVersion) == BufferTooSmall) {
            _ = bootServices.allocatePool(MemoryType.LoaderData, self.size, @ptrCast(*[*]align(8) u8, &self.map));
        }
    }
};

var memoryMapState = MemoryMap{};
pub const memoryMap = &memoryMapState;

pub fn initialize() void {
    memoryMap.refresh();
    const MemoryType = uefi.tables.MemoryType;
    const memoryDescEntries = memoryMap.size / memoryMap.descriptorSize;

    var totalMemory: usize = 0;
    var i: usize = 0;
    while (i < memoryDescEntries) : (i += 1) {
        const desc: *uefi.tables.MemoryDescriptor = &memoryMap.map[i];

        if (desc.type == MemoryType.ConventionalMemory) {
            totalMemory += desc.number_of_pages;
        }
    }

    totalMemory *= std.mem.page_size;
    memorySystemInfoState.totalAvailableMemory = totalMemory;
}
