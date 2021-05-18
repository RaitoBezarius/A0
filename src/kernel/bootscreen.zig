const std = @import("std");
const Allocator = std.mem.Allocator;
const graphics = @import("lib").graphics.Graphics;
const Color = @import("lib").graphics.Color;
const serial = @import("debug/serial.zig");
const platform = @import("platform.zig");
const scheduler = @import("scheduler.zig");
const Pixel = graphics.Pixel;

const rawBootVideo = @embedFile("bad_apple_1.yuv");
const VIDEO_W: u32 = 480;
const VIDEO_H: u32 = 360;
const VIDEO_DATA_LINE = VIDEO_W / 8;
const BYTES_PER_FRAME = VIDEO_DATA_LINE * VIDEO_H;
const N_FRAMES = rawBootVideo.len / BYTES_PER_FRAME;
const SLOW_FRAMES_START: u32 = 380;
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
var nextFrame: u64 = undefined;

fn showFrame(x_offset: u32, y_offset: u32, ratio: u32, iFrame: u32) void {
    nextFrame += FRAME_INTERVAL;
    if (iFrame >= SLOW_FRAMES_START) {
        nextFrame += 3 * FRAME_INTERVAL;
    }
    readFrameFromMonow(@ptrCast([*]const u8, rawBootVideo), iFrame);
    graphics.fromRawPixelsScale(x_offset, y_offset, VIDEO_W, VIDEO_H, rawPixelsPointer, ratio);

    while (scheduler.getElapsedTime() < nextFrame) {
        platform.ioWait(); // TODO(w) : sleep
    }
}

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
    nextFrame = scheduler.getElapsedTime();
    graphics.clear(Color.Black);
    while (iFrame < N_FRAMES) : (iFrame += 1) {
        showFrame(x_offset, y_offset, ratio, iFrame);
    }
    while (true) {
        var step: u32 = 1;
        while (step < 10) : (step += 1) {
            showFrame(x_offset, y_offset, ratio, iFrame - step - 1);
        }
        step -= 1;
        while (step > 0) : (step -= 1) {
            showFrame(x_offset, y_offset, ratio, iFrame - step);
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
