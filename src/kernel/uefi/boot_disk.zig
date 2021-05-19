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

fn listFilesRec(bs: *uefi.tables.BootServices, root: *uefi.protocols.FileProtocol) void {
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
   
    var fileInfoGuid align(8) = uefi.protocols.FileProtocol.guid;
    _ = root.getInfo(&fileInfoGuid, &bufferSize, buffer);
    var info = @ptrCast(*uefi.protocols.FileInfo, buffer);
    tty.print("File name : \"{s}\"\n", .{ @ptrCast([*:0]const u8, info.getFileName()) });
    const isDirectory: u64 = 0x10;

    if (info.attribute & isDirectory != 0) {
        tty.print("It's a directory !\n", .{});

        var entryBufferSize: usize = @sizeOf(uefi.protocols.FileInfo) + 260;
        var entryBuffer: [*]align(8) u8 = undefined;
        if (bs.allocatePool(uefi.tables.MemoryType.LoaderData, entryBufferSize, &entryBuffer) != uefi.Status.Success) {
            @panic("Failed to allocate a pool for directory information!\n");
        }

        if (root.read(&entryBufferSize, entryBuffer) != uefi.Status.Success) {
            @panic("Failed to read directory");
        }

        var entryInfo = @ptrCast(*uefi.protocols.FileInfo, buffer);
        tty.print("Entry name : \"{s}\"\n", .{ @ptrCast([*:0]const u8, entryInfo.getFileName()) });

        var entry: *uefi.protocols.FileProtocol = undefined;
        // Open in read mode, attributes are ignored in this case.
        if (root.open(&entry, entryInfo.getFileName(), 0x1, 0) != uefi.Status.Success) {
            @panic("Failed to open the entry");
        }

        listFilesRec(bs, entry);
    } else {
        tty.print("\tIt's a file !\n", .{});
    }
}

pub fn listFiles(bs: *uefi.tables.BootServices, fs: *uefi.protocols.SimpleFileSystemProtocol) void {
    var root: *uefi.protocols.FileProtocol = undefined;

    var status = fs.openVolume(&root);
    if (status != uefi.Status.Success) {
        @panic("Failed to open the volume described by a filesystem protocol!");
    }

    listFilesRec(bs, root);
}
