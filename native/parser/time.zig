const schema = @import("../schema/payload.zig");

pub const TimestampParts = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
};

pub fn parseIsoUtc(value: []const u8) schema.ParseError!TimestampParts {
    if (value.len != 20) return error.InvalidTimestamp;
    if (value[4] != '-' or value[7] != '-' or value[10] != 'T' or
        value[13] != ':' or value[16] != ':' or value[19] != 'Z')
    {
        return error.InvalidTimestamp;
    }

    const year = try parseFixed4(value[0..4]);
    const month = try parseFixed2(value[5..7]);
    const day = try parseFixed2(value[8..10]);
    const hour = try parseFixed2(value[11..13]);
    const minute = try parseFixed2(value[14..16]);
    const second = try parseFixed2(value[17..19]);

    if (month < 1 or month > 12) return error.InvalidTimestamp;
    if (day < 1 or day > daysInMonth(year, month)) return error.InvalidTimestamp;
    if (hour > 23 or minute > 59 or second > 59) return error.InvalidTimestamp;

    return .{
        .year = @intCast(year),
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
    };
}

pub fn dayOfWeek(ts: TimestampParts) u8 {
    const table = [_]u16{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    const adjusted_year: u32 = if (ts.month < 3)
        @intCast(ts.year - 1)
    else
        @intCast(ts.year);
    const month_index: usize = @intCast(ts.month - 1);
    const dow = (adjusted_year + adjusted_year / 4 - adjusted_year / 100 + adjusted_year / 400 +
        @as(u32, @intCast(table[month_index])) + @as(u32, @intCast(ts.day))) % 7;
    return @intCast((dow + 6) % 7);
}

pub fn minutesBetween(last: TimestampParts, current: TimestampParts) u32 {
    const last_days = daysSinceEpoch(last.year, last.month, last.day);
    const current_days = daysSinceEpoch(current.year, current.month, current.day);
    const last_minutes = last_days * 1440 + @as(i64, @intCast(last.hour)) * 60 + @as(i64, @intCast(last.minute));
    const current_minutes = current_days * 1440 + @as(i64, @intCast(current.hour)) * 60 + @as(i64, @intCast(current.minute));
    return @intCast(@max(current_minutes - last_minutes, 0));
}

fn parseFixed2(value: []const u8) schema.ParseError!u8 {
    if (value.len != 2 or !isDigit(value[0]) or !isDigit(value[1])) return error.InvalidTimestamp;
    return (value[0] - '0') * 10 + (value[1] - '0');
}

fn parseFixed4(value: []const u8) schema.ParseError!i32 {
    if (value.len != 4 or !isDigit(value[0]) or !isDigit(value[1]) or
        !isDigit(value[2]) or !isDigit(value[3]))
    {
        return error.InvalidTimestamp;
    }

    return @as(i32, @intCast(value[0] - '0')) * 1000 +
        @as(i32, @intCast(value[1] - '0')) * 100 +
        @as(i32, @intCast(value[2] - '0')) * 10 +
        @as(i32, @intCast(value[3] - '0'));
}

fn daysSinceEpoch(year: u16, month_u8: u8, day_u8: u8) i64 {
    var y: i32 = @intCast(year);
    const month: i32 = @intCast(month_u8);
    const day: i32 = @intCast(day_u8);

    y = if (month <= 2) y - 1 else y;
    const era = @divFloor(y, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const shifted_month: i32 = if (month > 2) month - 3 else month + 9;
    const doy = @divFloor(153 * shifted_month + 2, 5) + day - 1;
    const doe = yoe * 365 + yoe / 4 - yoe / 100 + @as(u32, @intCast(doy));
    return @as(i64, @intCast(era)) * 146097 + @as(i64, @intCast(doe)) - 719468;
}

fn daysInMonth(year: i32, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}
