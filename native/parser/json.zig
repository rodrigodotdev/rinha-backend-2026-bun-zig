const std = @import("std");
const schema = @import("../schema/payload.zig");
const time = @import("time.zig");

const KnownMerchants = struct {
    items: [schema.MAX_KNOWN_MERCHANTS][]const u8 = undefined,
    count: usize = 0,

    fn append(self: *KnownMerchants, merchant: []const u8) schema.ParseError!void {
        if (self.count >= self.items.len) return error.TooManyKnownMerchants;
        self.items[self.count] = merchant;
        self.count += 1;
    }

    fn contains(self: *const KnownMerchants, merchant: []const u8) bool {
        for (self.items[0..self.count]) |item| {
            if (std.mem.eql(u8, item, merchant)) return true;
        }
        return false;
    }
};

const LastTransactionFields = struct {
    minutes_since_last: u32,
    km_from_current: f32,
};

pub fn parse(buf: []const u8) schema.ParseError!schema.Payload {
    var p: usize = 0;

    try toNextValue(&p, buf);
    try skipString(&p, buf);

    try toNextValue(&p, buf);
    try toNextValue(&p, buf);
    const amount = try scanF32(&p, buf);

    try toNextValue(&p, buf);
    const installments = try scanU8Capped(&p, buf, 12);

    try toNextValue(&p, buf);
    const requested_at = try scanIso(&p, buf);

    try toNextValue(&p, buf);
    try toNextValue(&p, buf);
    const customer_avg_amount = try scanF32(&p, buf);

    try toNextValue(&p, buf);
    const tx_count_24h = try scanU32Capped(&p, buf, 20);

    try toNextValue(&p, buf);
    var known_merchants = KnownMerchants{};
    try scanKnownMerchants(&p, buf, &known_merchants);

    try toNextValue(&p, buf);
    try toNextValue(&p, buf);
    const merchant_id = try scanString(&p, buf);

    try toNextValue(&p, buf);
    const mcc = try scanMcc(&p, buf);

    try toNextValue(&p, buf);
    const merchant_avg_amount = try scanF32(&p, buf);

    try toNextValue(&p, buf);
    try toNextValue(&p, buf);
    const is_online = try scanBool(&p, buf);

    try toNextValue(&p, buf);
    const card_present = try scanBool(&p, buf);

    try toNextValue(&p, buf);
    const km_from_home = try scanF32(&p, buf);

    try toNextValue(&p, buf);
    if (p >= buf.len) return error.ExpectedValue;
    const has_last_tx = buf[p] != 'n';
    const last: LastTransactionFields = if (has_last_tx) blk: {
        if (buf[p] != '{') return error.ExpectedValue;
        try toNextValue(&p, buf);
        const last_timestamp = try scanIso(&p, buf);
        try toNextValue(&p, buf);
        const km = try scanF32(&p, buf);
        break :blk .{
            .minutes_since_last = time.minutesBetween(last_timestamp, requested_at),
            .km_from_current = km,
        };
    } else blk: {
        if (!std.mem.startsWith(u8, buf[p..], "null")) return error.ExpectedValue;
        break :blk .{
            .minutes_since_last = 0,
            .km_from_current = 0.0,
        };
    };

    return .{
        .amount = amount,
        .installments = installments,
        .hour = requested_at.hour,
        .day_of_week = time.dayOfWeek(requested_at),
        .customer_avg_amount = customer_avg_amount,
        .tx_count_24h = tx_count_24h,
        .mcc = mcc,
        .merchant_avg_amount = merchant_avg_amount,
        .is_online = is_online,
        .card_present = card_present,
        .km_from_home = km_from_home,
        .is_unknown_merchant = !known_merchants.contains(merchant_id),
        .has_last_tx = has_last_tx,
        .minutes_since_last = last.minutes_since_last,
        .km_from_current = last.km_from_current,
    };
}

fn toNextValue(p: *usize, buf: []const u8) schema.ParseError!void {
    while (true) {
        if (p.* > buf.len) return error.ExpectedValue;
        const rest = buf[p.*..];
        const colon = std.mem.indexOfScalar(u8, rest, ':');
        const quote = std.mem.indexOfScalar(u8, rest, '"');

        const pos = if (colon) |c|
            if (quote) |q| @min(c, q) else c
        else if (quote) |q|
            q
        else
            return error.ExpectedValue;

        p.* += pos;
        if (buf[p.*] == ':') {
            p.* += 1;
            skipWs(p, buf);
            return;
        }

        p.* += 1;
        const end = std.mem.indexOfScalar(u8, buf[p.*..], '"') orelse return error.InvalidString;
        p.* += end + 1;
    }
}

fn skipWs(p: *usize, buf: []const u8) void {
    while (p.* < buf.len and switch (buf[p.*]) {
        ' ', '\t', '\n', '\r' => true,
        else => false,
    }) {
        p.* += 1;
    }
}

fn skipString(p: *usize, buf: []const u8) schema.ParseError!void {
    if (p.* >= buf.len or buf[p.*] != '"') return error.InvalidString;
    p.* += 1;
    const end = std.mem.indexOfScalar(u8, buf[p.*..], '"') orelse return error.InvalidString;
    p.* += end + 1;
}

fn scanString(p: *usize, buf: []const u8) schema.ParseError![]const u8 {
    if (p.* >= buf.len or buf[p.*] != '"') return error.InvalidString;
    p.* += 1;
    const start = p.*;
    const end = std.mem.indexOfScalar(u8, buf[start..], '"') orelse return error.InvalidString;
    p.* = start + end + 1;
    return buf[start .. start + end];
}

fn scanKnownMerchants(p: *usize, buf: []const u8, known_merchants: *KnownMerchants) schema.ParseError!void {
    if (p.* >= buf.len or buf[p.*] != '[') return error.ExpectedValue;
    p.* += 1;

    while (p.* < buf.len and buf[p.*] != ']') {
        if (buf[p.*] == '"') {
            try known_merchants.append(try scanString(p, buf));
        } else {
            p.* += 1;
        }
    }

    if (p.* >= buf.len or buf[p.*] != ']') return error.ExpectedValue;
    p.* += 1;
}

fn scanF32(p: *usize, buf: []const u8) schema.ParseError!f32 {
    if (p.* > buf.len) return error.InvalidNumber;
    const parsed = try parseF32(buf[p.*..]);
    p.* += parsed.len;
    return parsed.value;
}

fn scanU32(p: *usize, buf: []const u8) schema.ParseError!u32 {
    var value: u32 = 0;
    var saw_digit = false;
    while (p.* < buf.len and isDigit(buf[p.*])) {
        saw_digit = true;
        const digit: u32 = @intCast(buf[p.*] - '0');
        if (value > (std.math.maxInt(u32) - digit) / 10) {
            value = std.math.maxInt(u32);
        } else {
            value = value * 10 + digit;
        }
        p.* += 1;
    }
    if (!saw_digit) return error.InvalidNumber;
    return value;
}

fn scanU8Capped(p: *usize, buf: []const u8, max_value: u8) schema.ParseError!u8 {
    const raw = try scanU32(p, buf);
    if (raw >= max_value) return max_value;
    return @intCast(raw);
}

fn scanU32Capped(p: *usize, buf: []const u8, max_value: u32) schema.ParseError!u32 {
    const raw = try scanU32(p, buf);
    return @min(raw, max_value);
}

fn scanBool(p: *usize, buf: []const u8) schema.ParseError!bool {
    if (p.* > buf.len) return error.ExpectedValue;
    if (std.mem.startsWith(u8, buf[p.*..], "true")) {
        p.* += 4;
        return true;
    }
    if (std.mem.startsWith(u8, buf[p.*..], "false")) {
        p.* += 5;
        return false;
    }
    return error.ExpectedValue;
}

fn scanMcc(p: *usize, buf: []const u8) schema.ParseError!u32 {
    if (p.* < buf.len and buf[p.*] == '"') p.* += 1;
    const value = try scanU32(p, buf);
    if (p.* < buf.len and buf[p.*] == '"') p.* += 1;
    return value;
}

fn scanIso(p: *usize, buf: []const u8) schema.ParseError!time.TimestampParts {
    const value = try scanString(p, buf);
    return time.parseIsoUtc(value);
}

const ParsedFloat = struct {
    value: f32,
    len: usize,
};

fn parseF32(input: []const u8) schema.ParseError!ParsedFloat {
    var pos: usize = 0;
    var negative = false;
    if (pos < input.len and input[pos] == '-') {
        negative = true;
        pos += 1;
    }

    var int_part: u64 = 0;
    var saw_digit = false;
    while (pos < input.len and isDigit(input[pos])) {
        saw_digit = true;
        const digit: u64 = @intCast(input[pos] - '0');
        if (int_part > (std.math.maxInt(u64) - digit) / 10) {
            int_part = std.math.maxInt(u64);
        } else {
            int_part = int_part * 10 + digit;
        }
        pos += 1;
    }
    if (!saw_digit) return error.InvalidNumber;

    var value: f64 = @floatFromInt(int_part);
    if (!std.math.isFinite(value)) return error.InvalidNumber;
    if (pos < input.len and input[pos] == '.') {
        pos += 1;
        var scale: f64 = 0.1;
        var saw_fraction_digit = false;
        while (pos < input.len and isDigit(input[pos])) {
            saw_fraction_digit = true;
            value += @as(f64, @floatFromInt(input[pos] - '0')) * scale;
            scale *= 0.1;
            pos += 1;
        }
        if (!saw_fraction_digit) return error.InvalidNumber;
    }

    if (pos < input.len and (input[pos] == 'e' or input[pos] == 'E')) {
        pos += 1;
        var exponent_sign: i32 = 1;
        if (pos < input.len and (input[pos] == '+' or input[pos] == '-')) {
            if (input[pos] == '-') exponent_sign = -1;
            pos += 1;
        }
        var exponent: i32 = 0;
        var saw_exponent_digit = false;
        while (pos < input.len and isDigit(input[pos])) {
            saw_exponent_digit = true;
            const digit: i32 = @intCast(input[pos] - '0');
            if (exponent > @divTrunc(std.math.maxInt(i32) - digit, 10)) {
                exponent = std.math.maxInt(i32);
            } else {
                exponent = exponent * 10 + digit;
            }
            pos += 1;
        }
        if (!saw_exponent_digit) return error.InvalidNumber;
        value *= std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exponent_sign * exponent)));
    }

    const signed = if (negative) -value else value;
    if (!std.math.isFinite(signed)) return error.InvalidNumber;
    if (signed > std.math.floatMax(f32) or signed < -std.math.floatMax(f32)) return error.InvalidNumber;
    return .{ .value = @floatCast(signed), .len = pos };
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}
