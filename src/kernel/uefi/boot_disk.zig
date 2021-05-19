const std = @import("std");
const uefi = std.os.uefi;
const SinglyLinkedList = @import("std").SinglyLinkedList;
const tty = @import("lib").graphics.Tty;

const DriverImageInfo = struct {
    len: u64,
    img: [*]u8,
};

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

fn truncateToUtf8(buffer: *[256]u8, utf16: [*:0]const u8) [*:0]const u8 {
    var i: u64 = 0;
    while (true) : (i += 1) {
        buffer[i] = utf16[2*i];
        if (utf16[2*i] == 0) {
            break;
        }
    }
    return @ptrCast([*:0]u8, buffer);
}

fn listFilesRec(bs: *uefi.tables.BootServices, root: *uefi.protocols.FileProtocol, list: *SinglyLinkedList(DriverImageInfo)) void {
    var bufferSize: usize = @sizeOf(uefi.protocols.FileInfo) + 260;
    var buffer: [*]align(8) u8 = undefined;
    if (bs.allocatePool(uefi.tables.MemoryType.LoaderData, bufferSize, &buffer) != uefi.Status.Success) {
        @panic("Failed to allocate a pool for directory information!\n");
    }

    var fileInfoGuid align(8) = uefi.protocols.FileProtocol.guid;
    if (root.getInfo(&fileInfoGuid, &bufferSize, buffer) != uefi.Status.Success) {
        @panic("Failed to acquire info on directory");
    }

    var info = @ptrCast(*uefi.protocols.FileInfo, buffer);
    const fileName = @ptrCast([*:0]const u8, info.getFileName());
    const isDirectory: u64 = 0x10;
    
    var entryBufferSize: usize = @sizeOf(uefi.protocols.FileInfo) + 260;
    var entryBuffer: [*]align(8) u8 = undefined;
    if (bs.allocatePool(uefi.tables.MemoryType.LoaderData, entryBufferSize, &entryBuffer) != uefi.Status.Success) {
        @panic("Failed to allocate a pool for directory information!\n");
    }

    if (info.attribute & isDirectory != 0) {
        while (true) {
            var currentSize = entryBufferSize;
            if (root.read(&currentSize, entryBuffer) != uefi.Status.Success) {
                @panic("Failed to read directory");
            }

            if (currentSize == 0) {
                break;
            }

            var entryInfo = @ptrCast(*uefi.protocols.FileInfo, entryBuffer);
            const entryName = @ptrCast([*:0]const u8, entryInfo.getFileName());

            var buf: [256]u8 = undefined;
            const printableName = truncateToUtf8(&buf, entryName);

            if (entryName[0] == '.') {
                continue;
            }

            var entry: *uefi.protocols.FileProtocol = undefined;
            // Open in read mode, attributes are ignored in this case.
            if (root.open(&entry, entryInfo.getFileName(), 0x1, 0) != uefi.Status.Success) {
                @panic("Failed to open the entry");
            }

            listFilesRec(bs, entry, list);
        }
    } else {
        var bufSize: usize = 4;
        var buf = [_]u8{ 0, 0, 0, 0 };
        if (root.read(&bufSize, &buf) != uefi.Status.Success) {
            @panic("Failed to read file");
        }

        if (buf[0] == 0x7f and buf[1] == 'E' and buf[2] == 'L' and buf[3] == 'F') {
            var nameBuf: [256]u8 = undefined;
            const printableName = truncateToUtf8(&nameBuf, fileName);

            tty.print("Driver file : {s}\n", .{ printableName });

            var contentBufferSize: usize = info.file_size + @sizeOf(SinglyLinkedList(DriverImageInfo));
            var contentBuffer: [*]align(8) u8 = undefined;
            if (bs.allocatePool(uefi.tables.MemoryType.LoaderData, contentBufferSize, &contentBuffer) != uefi.Status.Success) {
                @panic("Failed to allocate memory for the driver image !\n");
            }

            var imgSize = info.file_size;
            var imgBuffer: [*]align(8) u8 = contentBuffer + @sizeOf(SinglyLinkedList(DriverImageInfo));
            if (root.read(&imgSize, imgBuffer) != uefi.Status.Success) {
                @panic("Failed to read driver image !\n");
            }

            var node = @ptrCast(*SinglyLinkedList(DriverImageInfo).Node, contentBuffer);
            node.* = SinglyLinkedList(DriverImageInfo).Node{ .data = DriverImageInfo { .len = info.file_size, .img = imgBuffer } };
            list.prepend(node);
        }
    }
}

pub fn loadDriverImages(bs: *uefi.tables.BootServices, fs: *uefi.protocols.SimpleFileSystemProtocol) SinglyLinkedList(DriverImageInfo) {
    var root: *uefi.protocols.FileProtocol = undefined;

    var status = fs.openVolume(&root);
    if (status != uefi.Status.Success) {
        @panic("Failed to open the volume described by a filesystem protocol!");
    }

    var list: SinglyLinkedList(DriverImageInfo) = SinglyLinkedList(DriverImageInfo){};
    listFilesRec(bs, root, &list);

    return list;
}
