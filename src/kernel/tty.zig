const fmt = @import("std").fmt;
const platform = @import("arch/x86/platform.zig");
const graphics = @import("graphics.zig");
const Color = @import("color.zig");

const ttyState = packed struct {
    screen: graphics.Dimensions,
    fontSize: graphics.Dimensions,
    nbRows: u32,
    nbCols: u32,
};

pub fn initialize() void {
    graphics.clear(Color.Black);
}

const Errors = error {};

pub fn printCallback(context: void, string: []const u8) Errors!void {
    graphics.drawText(string);
}

pub fn print(comptime format: []const u8, args: ...,) void {
    _ = fmt.format({}, Errors, printCallback, format, args);
}

pub fn colorPrint(fg: u32, comptime format: []const u8, args: ...) void {
    const prevTextColor = graphics.getTextColor();
    graphics.setTextColor(fg);
    print(format, args);
    graphis.setTextColor(prevTextColor);
}

pub fn alignLeft(offset: usize) void {
    graphics.alignLeft(offset);
}

pub fn alignRight(offset: usize) void {
    alignLeft(SCREEN_MODE_WIDTH - offset);
}

pub fn alignCenter(strLen: usize) void {
    alignLeft((SCREEN_MODE_WIDTH - strLen) / 2);
}

pub fn panic(comptime format: []const u8, args: ...) noreturn {
    colorPrint(Color.White, "KERNEL PANIC: " ++ format ++ "\n", args);
    platform.hang();
}

pub fn step(comptime format: []const u8, args: ...) void {
    colorPrint(Color.LightBlue, ">> ");
    print(format ++ "...", args);
}

pub fn stepOK() void {
    const ok = " [ OK ]";

    alignRight(ok.len);
    colorPrint(Color.LightGreen, ok);
}
