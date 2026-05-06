const std = @import("std");
const vector_types = @import("vector_types");
const index_format = @import("index_format");

pub const BuiltIndex = struct {
    centroids_dim_major: []f32,
    list_offsets: []u32,
    list_sizes: []u32,
    vector_blocks: []i16,
    labels: []u8,
    block_count: u32,
    padded_count: u32,
    fraud_count: u32,
    legit_count: u32,
    max_list_size: u32,

    pub fn deinit(self: *BuiltIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.centroids_dim_major);
        allocator.free(self.list_offsets);
        allocator.free(self.list_sizes);
        allocator.free(self.vector_blocks);
        allocator.free(self.labels);
        self.* = .{
            .centroids_dim_major = &.{},
            .list_offsets = &.{},
            .list_sizes = &.{},
            .vector_blocks = &.{},
            .labels = &.{},
            .block_count = 0,
            .padded_count = 0,
            .fraud_count = 0,
            .legit_count = 0,
            .max_list_size = 0,
        };
    }
};

pub fn build(
    allocator: std.mem.Allocator,
    vectors: []const vector_types.Vector14,
    labels: []const u8,
    assignments: []const u16,
    centroids: []const vector_types.Vector14,
    centroid_count: u32,
) !BuiltIndex {
    if (vectors.len != labels.len or vectors.len != assignments.len) return error.LengthMismatch;
    const k: usize = @intCast(centroid_count);
    if (centroids.len != k) return error.LengthMismatch;

    var list_sizes = try allocator.alloc(u32, k);
    errdefer allocator.free(list_sizes);
    @memset(list_sizes, 0);
    for (assignments) |cell| {
        if (cell >= centroid_count) return error.InvalidAssignment;
        list_sizes[@intCast(cell)] += 1;
    }

    var list_offsets = try allocator.alloc(u32, k + 1);
    errdefer allocator.free(list_offsets);
    list_offsets[0] = 0;
    var block_cursor: u32 = 0;
    var max_list_size: u32 = 0;
    for (0..k) |cell| {
        const size = list_sizes[cell];
        if (size > max_list_size) max_list_size = size;
        const blocks = blocksForSize(size);
        block_cursor += blocks;
        list_offsets[cell + 1] = block_cursor;
    }

    const block_count = block_cursor;
    const padded_count = block_count * index_format.BLOCK_WIDTH;
    const vector_blocks = try allocator.alloc(i16, @as(usize, @intCast(block_count)) * index_format.BLOCK_LANES);
    errdefer allocator.free(vector_blocks);
    @memset(vector_blocks, index_format.PAD_VECTOR_LANE);

    const out_labels = try allocator.alloc(u8, padded_count);
    errdefer allocator.free(out_labels);
    @memset(out_labels, index_format.LABEL_LEGIT);

    const row_positions = try countingOrder(allocator, assignments, centroid_count, list_sizes);
    defer allocator.free(row_positions);

    var fraud_count: u32 = 0;
    var legit_count: u32 = 0;
    for (labels) |label| {
        if (label == index_format.LABEL_FRAUD) {
            fraud_count += 1;
        } else if (label == index_format.LABEL_LEGIT) {
            legit_count += 1;
        } else {
            return error.InvalidLabel;
        }
    }

    const out_centroids = try transposeCentroids(allocator, centroids, centroid_count);
    errdefer allocator.free(out_centroids);

    packBlocks(vectors, labels, row_positions, list_offsets, list_sizes, vector_blocks, out_labels);

    return .{
        .centroids_dim_major = out_centroids,
        .list_offsets = list_offsets,
        .list_sizes = list_sizes,
        .vector_blocks = vector_blocks,
        .labels = out_labels,
        .block_count = block_count,
        .padded_count = padded_count,
        .fraud_count = fraud_count,
        .legit_count = legit_count,
        .max_list_size = max_list_size,
    };
}

pub fn blocksForSize(size: u32) u32 {
    if (size == 0) return 0;
    return (size + index_format.BLOCK_WIDTH - 1) / index_format.BLOCK_WIDTH;
}

fn countingOrder(
    allocator: std.mem.Allocator,
    assignments: []const u16,
    centroid_count: u32,
    list_sizes: []const u32,
) ![]u32 {
    const k: usize = @intCast(centroid_count);
    var row_offsets = try allocator.alloc(u32, k);
    defer allocator.free(row_offsets);

    var row_cursor: u32 = 0;
    for (list_sizes, 0..) |size, cell| {
        row_offsets[cell] = row_cursor;
        row_cursor += size;
    }

    var cursors = try allocator.dupe(u32, row_offsets);
    defer allocator.free(cursors);

    var rows = try allocator.alloc(u32, assignments.len);
    for (assignments, 0..) |cell, row| {
        const index: usize = @intCast(cell);
        const position = cursors[index];
        rows[@intCast(position)] = @intCast(row);
        cursors[index] += 1;
    }

    return rows;
}

fn packBlocks(
    vectors: []const vector_types.Vector14,
    input_labels: []const u8,
    row_positions: []const u32,
    list_offsets: []const u32,
    list_sizes: []const u32,
    vector_blocks: []i16,
    labels: []u8,
) void {
    var row_base: usize = 0;
    for (list_sizes, 0..) |size, cell| {
        var offset_in_list: u32 = 0;
        while (offset_in_list < size) : (offset_in_list += 1) {
            const row: usize = @intCast(row_positions[row_base + offset_in_list]);
            const global_block = list_offsets[cell] + (offset_in_list / index_format.BLOCK_WIDTH);
            const slot: usize = @intCast(offset_in_list % index_format.BLOCK_WIDTH);
            const block_origin = @as(usize, @intCast(global_block)) * index_format.BLOCK_LANES;
            inline for (0..14) |dim| {
                const lane = block_origin + dim * @as(usize, index_format.BLOCK_WIDTH) + slot;
                vector_blocks[lane] = quantize(vectors[row][dim]);
            }
            labels[@as(usize, @intCast(global_block)) * @as(usize, index_format.BLOCK_WIDTH) + slot] = input_labels[row];
        }
        row_base += size;
    }
}

fn quantize(value: f32) i16 {
    const scaled = @round(value * @as(f32, @floatFromInt(index_format.VECTOR_SCALE_DENOMINATOR)));
    const min_lane: f32 = @floatFromInt(std.math.minInt(i16));
    const max_lane: f32 = @floatFromInt(std.math.maxInt(i16));
    const clamped = @max(min_lane, @min(max_lane, scaled));
    return @intFromFloat(clamped);
}

fn transposeCentroids(
    allocator: std.mem.Allocator,
    centroids: []const vector_types.Vector14,
    centroid_count: u32,
) ![]f32 {
    const k: usize = @intCast(centroid_count);
    var out_centroids = try allocator.alloc(f32, k * @as(usize, index_format.DIMENSIONS));
    for (0..k) |ci| {
        inline for (0..14) |dim| {
            out_centroids[dim * k + ci] = centroids[ci][dim];
        }
    }
    return out_centroids;
}

pub fn writeBinaryIo(io: std.Io, dir: std.Io.Dir, output_name: []const u8, layout: index_format.Layout, built: *const BuiltIndex) !void {
    var tmp_name_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const tmp_name = try std.fmt.bufPrint(&tmp_name_buf, "{s}.tmp", .{output_name});

    dir.deleteFile(io, tmp_name) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const file = try dir.createFile(io, tmp_name, .{ .truncate = true });
    errdefer dir.deleteFile(io, tmp_name) catch {};
    defer file.close(io);

    const header = index_format.encodeHeader(layout);
    try file.writeStreamingAll(io, &header);
    try writeF32Slice(io, file, built.centroids_dim_major);
    try writeU32Slice(io, file, built.list_offsets);
    try writeU32Slice(io, file, built.list_sizes);
    try writeI16Slice(io, file, built.vector_blocks);
    try file.writeStreamingAll(io, built.labels);
    try file.sync(io);

    try dir.rename(tmp_name, dir, output_name, io);
}

pub fn writeBinaryPathIo(io: std.Io, cwd: std.Io.Dir, output_path: []const u8, layout: index_format.Layout, built: *const BuiltIndex) !void {
    if (std.fs.path.dirname(output_path)) |dirname| {
        var dir = if (std.fs.path.isAbsolute(dirname))
            try std.Io.Dir.openDirAbsolute(io, dirname, .{})
        else
            try cwd.openDir(io, dirname, .{});
        defer dir.close(io);
        return writeBinaryIo(io, dir, std.fs.path.basename(output_path), layout, built);
    }

    return writeBinaryIo(io, cwd, output_path, layout, built);
}

fn writeF32Slice(io: std.Io, file: std.Io.File, values: []const f32) !void {
    var buf: [4]u8 = undefined;
    for (values) |value| {
        const bits: u32 = @bitCast(value);
        std.mem.writeInt(u32, &buf, bits, .little);
        try file.writeStreamingAll(io, &buf);
    }
}

fn writeU32Slice(io: std.Io, file: std.Io.File, values: []const u32) !void {
    var buf: [4]u8 = undefined;
    for (values) |value| {
        std.mem.writeInt(u32, &buf, value, .little);
        try file.writeStreamingAll(io, &buf);
    }
}

fn writeI16Slice(io: std.Io, file: std.Io.File, values: []const i16) !void {
    var buf: [2]u8 = undefined;
    for (values) |value| {
        std.mem.writeInt(i16, &buf, value, .little);
        try file.writeStreamingAll(io, &buf);
    }
}
