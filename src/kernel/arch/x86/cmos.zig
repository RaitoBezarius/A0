const platform = @import("platform.zig");
const serial = @import("../../debug/serial.zig");

const CMOS_ADDR = 0x70;
const CMOS_DATA = 0x71;

fn read_cmos_reg(comptime reg: u8) u8 {
    platform.out(CMOS_ADDR, reg);
    return platform.in(u8, CMOS_DATA);
}

pub fn read_date() platform.Date {
    platform.cli();
    var date = platform.Date{
        .second = read_cmos_reg(0x00),
        .minute = read_cmos_reg(0x02),
        .hour = read_cmos_reg(0x04),
        .day = read_cmos_reg(0x07),
        .month = read_cmos_reg(0x08),
        .year = read_cmos_reg(0x09),
        .century = read_cmos_reg(0x32),
    };
    var registerB = read_cmos_reg(0x0B);
    platform.sti();
    platform.NMI_enable();

    if (registerB & 0x04 == 0) {
        date.second = (date.second & 0x0F) + ((date.second / 16) * 10);
        date.minute = (date.minute & 0x0F) + ((date.minute / 16) * 10);
        date.hour = ((date.hour & 0x0F) + (((date.hour & 0x70) / 16) * 10)) | (date.hour & 0x80);
        date.day = (date.day & 0x0F) + ((date.day / 16) * 10);
        date.month = (date.month & 0x0F) + ((date.month / 16) * 10);
        date.year = (date.year & 0x0F) + ((date.year / 16) * 10);
        date.century = (date.century & 0x0F) + ((date.century / 16) * 10);
    }
    return date;
}
