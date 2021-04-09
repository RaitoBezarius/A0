const uefi = @import("std").os.uefi;
const fmt = @import("std").fmt;

var enabled: bool = false;
var conOut: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var conIn: *uefi.protocols.SimpleTextInputProtocol = undefined;

pub fn puts(msg: []const u8) void {
    if (enabled) {
        for (msg) |c| {
            const c_ = [2]u16{ c, 0 };
            _ = conOut.outputString(@ptrCast(*const [1:0]u16, &c_));
        }
    }
}

pub fn printf(buf: []u8, comptime format: []const u8, args: anytype) void {
    if (enabled) {
        puts(fmt.bufPrint(buf, format, args) catch unreachable);
    }
}

pub fn initialize() void {
    conOut = uefi.system_table.con_out.?;
    conIn = uefi.system_table.con_in.?;

    enabled = true;
    puts("Low-level debugging console initialized.\r\n");
}

pub fn disable() void {
    enabled = false;
}
