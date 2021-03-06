const uefi = @import("std").os.uefi;
const L = @import("std").unicode.utf8ToUtf16LeStringLiteral;

pub fn main() void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.outputString(L("Hello world, A0, from UEFI!\r\n"));
}
