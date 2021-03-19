pub const PAGE_SIZE: usize = 4096;

fn intOrPtr(comptime T: type, address: usize) T {
    return if (T == usize) address else @intToPtr(T, address);
}

fn int(address: anytype) usize {
    return if (@TypeOf(address) == usize) address else @ptrToInt(address);
}

pub fn pageBase(address: anytype) @TypeOf(address) {
    const result = int(address) & (~PAGE_SIZE +% 1);

    return intOrPtr(@TypeOf(address), result);
}

pub fn pageAlign(address: anytype) @TypeOf(address) {
    const result = (int(address) + PAGE_SIZE - 1) & (~PAGE_SIZE +% 1);

    return intOrPtr(@TypeOf(address), result);
}
