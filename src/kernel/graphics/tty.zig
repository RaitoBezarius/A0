const std = @import("std");
const fmt = std.fmt;
const platform = @import("../arch/x86/platform.zig");
const graphics = @import("graphics.zig");
const psf2 = @import("../fonts/psf2.zig");
const Dimensions = graphics.Dimensions;
const Position = graphics.Position;
const Color = @import("color.zig");
const serial = @import("../debug/serial.zig");

const TtyState = struct {
    screen: Dimensions, // Size in pixels
    fontSize: Dimensions,
    nbRows: u32, // Size of screen in characters
    nbCols: u32,
};
var state: TtyState = undefined;
const TAB_SIZE = 8;

pub fn initialize() void {
    var font = psf2.asFont(psf2.defaultFont);
    var screen = graphics.getDimensions();

    state = TtyState{
        .screen = screen,
        .fontSize = .{
            .height = font.height,
            .width = font.width,
        },
        .nbRows = screen.height / font.height,
        .nbCols = screen.width / font.width,
    };

    graphics.clear(Color.Black);
    graphics.setCursorCoords(0, 0);
}

fn isCharControl(char: u8) bool {
    return char < 32 or char > 126;
}

const Errors = error{};

fn getCursorCharRow() i32 {
    return @divTrunc(graphics.getCursorPos().y, @intCast(i32, state.fontSize.height));
}
fn getCursorCharCol() i32 {
    return @divTrunc(graphics.getCursorPos().x, @intCast(i32, state.fontSize.width));
}

fn newLine() void {
    var cursor = graphics.getCursorPos();
    if (getCursorCharRow() >= state.nbRows) {
        graphics.scroll(state.fontSize.height);
        graphics.setCursorCoords(0, cursor.y);
    } else {
        graphics.setCursorCoords(0, cursor.y + @intCast(i32, state.fontSize.height));
    }
}

const ScreenWritter = struct {
    pub const Error = Errors;
    pub const Writer = std.io.Writer(*ScreenWritter, Error, write);

    pub fn writer(self: *ScreenWritter) Writer {
        return .{ .context = self };
    }

    pub fn write(self: *ScreenWritter, string: []const u8) Error!usize {
        if (isCharControl(string[0])) {
            var cursor = graphics.getCursorPos();
            switch (string[0]) {
                '\n' => {
                    newLine();
                },
                '\x08' => { // backspace
                    var cur_w = @intCast(i32, state.fontSize.width);
                    if (cursor.x >= cur_w) {
                        graphics.setCursorCoords(cursor.x - cur_w, cursor.y);
                        graphics.drawText(" ");
                        graphics.setCursorCoords(cursor.x - cur_w, cursor.y);
                    }
                },
                '\t' => { // Tabulation
                    var tab_w = @intCast(i32, state.fontSize.width) * TAB_SIZE;
                    var x = @divTrunc(cursor.x, tab_w) * tab_w;
                    if (x + tab_w >= @intCast(i32, state.screen.width)) {
                        newLine();
                        cursor.y = graphics.getCursorPos().y;
                        x = 0;
                    }
                    graphics.setCursorCoords(x + tab_w, cursor.y);
                },
                '\r' => { // Cariage return
                    graphics.setCursorCoords(0, cursor.y);
                },
                else => {
                    serial.printf("Unknown control char {}\n", .{@intCast(u32, string[0])});
                },
            }
            return 1;
        } else {
            var len = string.len;
            var remainingOnLine = @intCast(i32, state.nbCols) - getCursorCharCol();
            if (remainingOnLine <= 0) {
                newLine();
                remainingOnLine = @intCast(i32, state.nbCols);
            }
            if (remainingOnLine < len) {
                len = @intCast(u32, remainingOnLine);
            }
            var realLen: usize = 0;
            while (realLen < len) : (realLen += 1) {
                if (isCharControl(string[realLen])) {
                    break;
                }
            }
            graphics.drawText(string[0..realLen]);
            return realLen;
        }
    }
};
var screenWritter = ScreenWritter{};

pub fn print(comptime format: []const u8, args: anytype) void {
    fmt.format(screenWritter.writer(), format, args) catch |err| {
        serial.ppanic("Failed print: {}", .{err});
    };
}

pub fn serialPrint(comptime format: []const u8, args: anytype) void {
    print(format, args);
    serial.printf(format, args);
}

pub fn colorPrint(fg: ?u32, bg: ?u32, comptime format: []const u8, args: anytype) void {
    const prevTextColor = graphics.getTextColor();
    graphics.setTextColor(fg, bg);
    print(format, args);
    graphics.setTextColor(prevTextColor.fg, prevTextColor.bg);
}

pub fn alignLeft(offset: usize) void {
    graphics.textAlignLeft(offset);
}

pub fn alignRight(offset: usize) void {
    alignLeft(state.nbCols - offset);
}

pub fn alignCenter(strLen: usize) void {
    alignLeft((state.nbCols - strLen) / 2);
}

pub fn panic(comptime format: []const u8, args: anytype) noreturn {
    colorPrint(Color.White, null, "KERNEL PANIC: " ++ format ++ "\n", args);
    serial.writeText("\n!!!!!!!!!!!!! KERNEL PANIC !!!!!!!!!!!!!!!\n");
    serial.printf(format ++ "\n", args);
    platform.hang();
}

pub fn step(comptime format: []const u8, args: anytype) void {
    colorPrint(Color.LightBlue, null, ">> ", .{});
    print(format ++ "...", args);
}

pub fn stepOK() void {
    const ok = " [ OK ]";

    alignRight(ok.len);
    colorPrint(Color.LightGreen, null, ok, .{});
}

pub fn selfTest() void {
    print("{s}", .{">>>\tLorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce vitae ex eros. Suspendisse a purus at lorem porta porttitor quis a arcu. Aenean hendrerit arcu sed mi tincidunt auctor. Aliquam lorem mauris, semper eu erat ac, commodo sollicitudin ex. Aliquam non lorem vitae arcu posuere suscipit eget in eros. Aenean ultrices mauris quis est vestibulum, eu fringilla diam laoreet. Donec ornare erat nisi, a lobortis mauris pulvinar ut. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Donec euismod mi in sapien lacinia, vel consectetur risus pretium.X\x08\n\n"});
    colorPrint(Color.LightGreen, Color.Red, "This is a green text on red\n", .{});
    serialPrint("TTY self test completed.\n", .{});
}
