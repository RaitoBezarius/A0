const std = @import("std");
const uefi = std.os.uefi;
const tty = @import("lib").graphics.Tty;

pub fn enumerateAllFSProtocols(bootServices: *uefi.tables.BootServices) *uefi.protocols.SimpleFileSystemProtocol {
    var handleCount: usize = 0;
    var handles: [*]uefi.Handle = undefined;
    var status = bootServices.locateHandleBuffer(uefi.tables.LocateSearchType.ByProtocol, &uefi.protocols.SimpleFileSystemProtocol.guid, null, &handleCount, &handles);

    if (status != uefi.Status.Success) {
        @panic("Failed to locate handle buffer for simple filesystem !");
    }

    var fs: *uefi.protocols.SimpleFileSystemProtocol = undefined;
    status = bootServices.handleProtocol(handles[0], &uefi.protocols.SimpleFileSystemProtocol.guid, @ptrCast(*?*c_void, &fs));

    if (status != uefi.Status.Success) {
        @panic("Failed to handle protocol for the handle returned !");
    }

    return fs;
}

pub fn listFiles(bs: *uefi.tables.BootServices, fs: *uefi.protocols.SimpleFileSystemProtocol) void {
    var root: *uefi.protocols.FileProtocol = undefined;

    var status = fs.openVolume(&root);
    if (status != uefi.Status.Success) {
        @panic("Failed to open the volume described by a filesystem protocol!");
    }

    var bufferSize: usize = @sizeOf(uefi.protocols.FileInfo) + 260;
    var buffer: [*]align(8) u8 = undefined;
    if (bs.allocatePool(uefi.tables.MemoryType.LoaderData, bufferSize, &buffer) != uefi.Status.Success) {
        @panic("Failed to allocate a pool for directory information!\n");
    }

    // TODO(thejohncrafter)
    // Read the root directory, it provides [*]uefi.protocols.FileProtocol.FileInfo
    // bufferSize + 260 as fat32 has 256 chars filename limits. This should prevents BufferTooSmall returns.
    // If it's a directory, recursively listFiles inside of it.
    // If it's a file, filter out non ELF files, read the first bytes of it to find out
    // if it has ELF64 magic header.
    // Once it's indeed an ELF file, enqueue it inside the structure of servers to load.
    // Destroy the rest.
}
