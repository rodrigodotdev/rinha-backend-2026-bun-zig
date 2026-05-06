const std = @import("std");
const index_format = @import("format.zig");

pub const IndexView = struct {
    layout: index_format.Layout,
    centroids_dim_major: []const f32,
    list_offsets: []const u32,
    list_sizes: []const u32,
    vector_blocks: []const i16,
    labels: []const u8,
};

pub const MappedIndex = struct {
    file: std.Io.File,
    map: std.Io.File.MemoryMap,
    view: IndexView,

    pub fn deinit(self: *MappedIndex, io: std.Io) void {
        self.map.destroy(io);
        self.file.close(io);
        self.* = undefined;
    }
};

pub fn loadFromDir(io: std.Io, dir: std.Io.Dir, path: []const u8) !MappedIndex {
    const file = try dir.openFile(io, path, .{});
    errdefer file.close(io);

    const stat = try file.stat(io);
    if (stat.size < index_format.HEADER_SIZE) return error.IndexTooSmall;
    if (stat.size > std.math.maxInt(usize)) return error.IndexTooLarge;

    var map = try file.createMemoryMap(io, .{
        .len = @intCast(stat.size),
        .protection = .{ .read = true, .write = false },
        .populate = true,
    });
    errdefer map.destroy(io);

    const readonly = map.memory[0..@intCast(stat.size)];
    const view = try viewFromBytes(readonly);
    return .{ .file = file, .map = map, .view = view };
}

pub fn loadDefault(io: std.Io) !MappedIndex {
    const cwd = std.Io.Dir.cwd();
    return loadFromDir(io, cwd, "fraud-index.bin") catch |first_err| switch (first_err) {
        error.FileNotFound => loadFromDir(io, cwd, "resources/fraud-index.bin"),
        else => first_err,
    };
}

pub fn viewFromBytes(bytes: []const u8) !IndexView {
    if (bytes.len < index_format.HEADER_SIZE) return error.IndexTooSmall;

    const header_bytes: *const [index_format.HEADER_SIZE]u8 = bytes[0..index_format.HEADER_SIZE];
    const layout = try index_format.decodeHeader(header_bytes);
    try validateLayout(layout, bytes.len);

    const centroids_bytes = try section(bytes, layout.centroids_offset, layout.list_offsets_offset);
    const list_offsets_bytes = try section(bytes, layout.list_offsets_offset, layout.list_sizes_offset);
    const list_sizes_bytes = try section(bytes, layout.list_sizes_offset, layout.vectors_offset);
    const vectors_bytes = try section(bytes, layout.vectors_offset, layout.labels_offset);
    const labels = try section(bytes, layout.labels_offset, layout.file_size);

    const centroids = try bytesAsAlignedSlice(f32, centroids_bytes);
    const list_offsets = try bytesAsAlignedSlice(u32, list_offsets_bytes);
    const list_sizes = try bytesAsAlignedSlice(u32, list_sizes_bytes);
    const vectors = try bytesAsAlignedSlice(i16, vectors_bytes);

    try validateSections(layout, centroids, list_offsets, list_sizes, vectors, labels);

    return .{
        .layout = layout,
        .centroids_dim_major = centroids,
        .list_offsets = list_offsets,
        .list_sizes = list_sizes,
        .vector_blocks = vectors,
        .labels = labels,
    };
}

fn validateLayout(layout: index_format.Layout, file_size: usize) !void {
    if (layout.header_size != index_format.HEADER_SIZE) return error.BadHeaderSize;
    if (layout.dimensions != index_format.DIMENSIONS) return error.BadDimensions;
    if (layout.block_width != index_format.BLOCK_WIDTH) return error.BadBlockWidth;
    if (layout.vector_encoding != index_format.VECTOR_ENCODING_I16_Q10000) return error.BadVectorEncoding;
    if (layout.vector_scale_denominator != index_format.VECTOR_SCALE_DENOMINATOR) return error.BadVectorScale;
    if (layout.centroid_layout != index_format.CENTROIDS_DIM_MAJOR) return error.BadCentroidLayout;
    if (layout.file_size > std.math.maxInt(usize)) return error.IndexTooLarge;
    if (layout.file_size != file_size) return error.BadFileSize;
    if (layout.centroid_count == 0 or layout.centroid_count > index_format.DEFAULT_CENTROID_COUNT) return error.BadCentroidCount;
    if (layout.block_count == 0) return error.BadBlockCount;
    if (layout.padded_count != layout.block_count * index_format.BLOCK_WIDTH) return error.BadPaddedCount;
    if (layout.fraud_count + layout.legit_count != layout.vector_count) return error.BadLabelCounts;
    if (!(layout.centroids_offset < layout.list_offsets_offset and
        layout.list_offsets_offset < layout.list_sizes_offset and
        layout.list_sizes_offset < layout.vectors_offset and
        layout.vectors_offset < layout.labels_offset and
        layout.labels_offset < layout.file_size))
    {
        return error.BadSectionOrder;
    }
    if (!isAligned(layout.centroids_offset, @alignOf(f32))) return error.BadSectionAlignment;
    if (!isAligned(layout.list_offsets_offset, @alignOf(u32))) return error.BadSectionAlignment;
    if (!isAligned(layout.list_sizes_offset, @alignOf(u32))) return error.BadSectionAlignment;
    if (!isAligned(layout.vectors_offset, @alignOf(i16))) return error.BadSectionAlignment;
}

fn validateSections(
    layout: index_format.Layout,
    centroids: []const f32,
    list_offsets: []const u32,
    list_sizes: []const u32,
    vector_blocks: []const i16,
    labels: []const u8,
) !void {
    const centroid_count: usize = @intCast(layout.centroid_count);
    const block_count: usize = @intCast(layout.block_count);
    const padded_count: usize = @intCast(layout.padded_count);
    if (centroids.len != centroid_count * @as(usize, index_format.DIMENSIONS)) return error.BadCentroidsSection;
    if (list_offsets.len != centroid_count + 1) return error.BadListOffsetsSection;
    if (list_sizes.len != centroid_count) return error.BadListSizesSection;
    if (vector_blocks.len != block_count * index_format.BLOCK_LANES) return error.BadVectorSection;
    if (labels.len != padded_count) return error.BadLabelsSection;
    if (list_offsets[0] != 0) return error.BadListOffsets;
    if (list_offsets[list_offsets.len - 1] != layout.block_count) return error.BadListOffsets;

    var vector_sum: u64 = 0;
    for (0..list_sizes.len) |i| {
        if (list_offsets[i] > list_offsets[i + 1]) return error.BadListOffsets;
        const block_capacity = (list_offsets[i + 1] - list_offsets[i]) * index_format.BLOCK_WIDTH;
        if (list_sizes[i] > block_capacity) return error.BadListSize;
        vector_sum += list_sizes[i];
    }
    if (vector_sum != layout.vector_count) return error.BadVectorCount;
}

fn section(bytes: []const u8, start: u64, end: u64) ![]const u8 {
    if (start > end) return error.BadSectionOrder;
    if (end > bytes.len) return error.BadSectionBounds;
    return bytes[@intCast(start)..@intCast(end)];
}

fn bytesAsAlignedSlice(comptime T: type, bytes: []const u8) ![]const T {
    if (bytes.len % @sizeOf(T) != 0) return error.BadSectionSize;
    const aligned: []align(@alignOf(T)) const u8 = @alignCast(bytes);
    return std.mem.bytesAsSlice(T, aligned);
}

fn isAligned(offset: u64, comptime alignment: u64) bool {
    return offset % alignment == 0;
}
