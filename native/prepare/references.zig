const std = @import("std");
const vector_types = @import("vector_types");
const index_format = @import("index_format");

pub const ReferenceSet = struct {
    vectors: []vector_types.Vector14,
    labels: []u8,
    fraud_count: u32,
    legit_count: u32,

    pub fn deinit(self: *ReferenceSet, allocator: std.mem.Allocator) void {
        allocator.free(self.vectors);
        allocator.free(self.labels);
        self.* = .{ .vectors = &.{}, .labels = &.{}, .fraud_count = 0, .legit_count = 0 };
    }
};

pub fn parseSlice(allocator: std.mem.Allocator, input: []const u8) !ReferenceSet {
    var scanner = std.json.Scanner.initCompleteInput(allocator, input);
    defer scanner.deinit();
    return parseTokenSource(allocator, &scanner);
}

pub fn parseTokenSource(allocator: std.mem.Allocator, source: anytype) !ReferenceSet {
    var vectors: std.ArrayListUnmanaged(vector_types.Vector14) = .empty;
    var labels: std.ArrayListUnmanaged(u8) = .empty;
    errdefer vectors.deinit(allocator);
    errdefer labels.deinit(allocator);

    if (try source.next() != .array_begin) return error.ExpectedArray;

    var fraud_count: u32 = 0;
    var legit_count: u32 = 0;

    while (true) {
        const next = try source.peekNextTokenType();
        if (next == .array_end) {
            _ = try source.next();
            break;
        }

        const record = try parseRecord(allocator, source);
        try vectors.append(allocator, record.vector);
        try labels.append(allocator, record.label);
        if (record.label == index_format.LABEL_FRAUD) fraud_count += 1 else legit_count += 1;
    }

    return .{
        .vectors = try vectors.toOwnedSlice(allocator),
        .labels = try labels.toOwnedSlice(allocator),
        .fraud_count = fraud_count,
        .legit_count = legit_count,
    };
}

const Record = struct {
    vector: vector_types.Vector14,
    label: u8,
};

fn parseRecord(allocator: std.mem.Allocator, source: anytype) !Record {
    if (try source.next() != .object_begin) return error.ExpectedObject;

    var vector: vector_types.Vector14 = undefined;
    var saw_vector = false;
    var label: u8 = index_format.LABEL_LEGIT;
    var saw_label = false;

    while (true) {
        const token = try source.nextAlloc(allocator, .alloc_if_needed);
        defer freeToken(allocator, token);

        switch (token) {
            .object_end => break,
            .string, .allocated_string => |key| {
                if (std.mem.eql(u8, key, "vector")) {
                    vector = try parseVector(allocator, source);
                    saw_vector = true;
                } else if (std.mem.eql(u8, key, "label")) {
                    label = try parseLabel(allocator, source);
                    saw_label = true;
                } else {
                    try source.skipValue();
                }
            },
            else => return error.ExpectedObjectKey,
        }
    }

    if (!saw_vector) return error.MissingVector;
    if (!saw_label) return error.MissingLabel;
    return .{ .vector = vector, .label = label };
}

fn parseVector(allocator: std.mem.Allocator, source: anytype) !vector_types.Vector14 {
    if (try source.next() != .array_begin) return error.ExpectedVectorArray;
    var out: vector_types.Vector14 = undefined;
    var index: usize = 0;
    while (index < out.len) : (index += 1) {
        const token = try source.nextAlloc(allocator, .alloc_if_needed);
        defer freeToken(allocator, token);
        const raw = switch (token) {
            .number, .allocated_number => |n| n,
            else => return error.ExpectedNumber,
        };
        out[index] = try std.fmt.parseFloat(f32, raw);
    }
    if (try source.next() != .array_end) return error.TooManyVectorDimensions;
    return out;
}

fn parseLabel(allocator: std.mem.Allocator, source: anytype) !u8 {
    const token = try source.nextAlloc(allocator, .alloc_if_needed);
    defer freeToken(allocator, token);
    const raw = switch (token) {
        .string, .allocated_string => |s| s,
        else => return error.ExpectedLabel,
    };
    if (std.mem.eql(u8, raw, "fraud")) return index_format.LABEL_FRAUD;
    if (std.mem.eql(u8, raw, "legit")) return index_format.LABEL_LEGIT;
    return error.InvalidLabel;
}

fn freeToken(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_string, .allocated_number => |value| allocator.free(value),
        else => {},
    }
}
