const std = @import("std");
const Allocator = std.mem.Allocator;
const graphics = @import("graphics.zig");
const Color = @import("color.zig");
const serial = @import("../debug/serial.zig");
const platform = @import("../platform.zig");
const scheduler = @import("../scheduler.zig");
const Pixel = graphics.Pixel;

const rawBootVideo = @embedFile("bad_apple_1.yuv");
const VIDEO_W: u32 = 480;
const VIDEO_H: u32 = 360;
const VIDEO_DATA_LINE = VIDEO_W / 8;
const BYTES_PER_FRAME = VIDEO_DATA_LINE * VIDEO_H;
const N_FRAMES = rawBootVideo.len / BYTES_PER_FRAME;
const FRAME_INTERVAL: u64 = 33300000;

const WHITE_PIXEL = graphics.pixelFromColor(Color.White);
const BLACK_PIXEL = graphics.pixelFromColor(Color.Black);

var rawPixels: [VIDEO_W * VIDEO_H]Pixel = undefined;
const rawPixelsPointer = @ptrCast([*]Pixel, &rawPixels);

fn readFrameFromMonow(rawPtr: [*]const u8, iFrame: u32) void {
    var framePtr = rawPtr + iFrame * BYTES_PER_FRAME;
    var rawPixelsPtr = rawPixelsPointer;
    var iByte: u32 = 0;
    while (iByte < BYTES_PER_FRAME) : (iByte += 1) {
        var byte = framePtr[iByte];
        var iBit: u32 = 8;
        while (iBit > 0) {
            iBit -= 1;
            var bit = (byte >> @truncate(u3, iBit)) & 1;
            rawPixelsPtr[0] = if (bit == 0) BLACK_PIXEL else WHITE_PIXEL;
            rawPixelsPtr += 1;
        }
    }
}

var boot_task: *scheduler.Task = undefined;

fn runBootVideo() void {
    var screen = graphics.getDimensions();
    var ratio = screen.height / VIDEO_H;
    var ratio_w = screen.width / VIDEO_W;
    if (ratio > ratio_w) {
        ratio = ratio_w;
    }
    var x_offset = (screen.width - VIDEO_W * ratio) / 2;
    var y_offset = (screen.height - VIDEO_H * ratio) / 2;

    var iFrame: u32 = 0;
    var nextFrame = scheduler.getElapsedTime();
    graphics.clear(Color.Black);
    while (iFrame < N_FRAMES) : (iFrame += 1) {
        nextFrame += FRAME_INTERVAL;
        readFrameFromMonow(@ptrCast([*]const u8, rawBootVideo), iFrame);
        graphics.fromRawPixelsScale(x_offset, y_offset, VIDEO_W, VIDEO_H, rawPixelsPointer, ratio);

        while (scheduler.getElapsedTime() < nextFrame) {
            platform.ioWait(); // TODO(w) : sleep
        }
    }
    boot_task.state = scheduler.TaskState.Stopped;
    while (true) {
        platform.ioWait(); // TODO(w) : exit
    }
}

pub fn bootVideo(allocator: *Allocator) Allocator.Error!void {
    boot_task = try scheduler.Task.create(@ptrToInt(runBootVideo), true, allocator, 0);
    try scheduler.scheduleNewTask(boot_task, allocator);
}
