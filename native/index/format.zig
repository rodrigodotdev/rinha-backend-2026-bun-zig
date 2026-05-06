const std = @import("std");

pub const MAGIC: [8]u8 = .{ 'R', 'I', 'V', 'F', '0', '0', '0', '1' };
pub const VERSION: u32 = 1;
pub const HEADER_SIZE: usize = 128;
pub const DIMENSIONS: u32 = 14;
pub const DEFAULT_CENTROID_COUNT: u32 = 4096;
pub const BLOCK_WIDTH: u32 = 8;
pub const BLOCK_LANES: usize = DIMENSIONS * BLOCK_WIDTH;
pub const VECTOR_ENCODING_I16_Q10000: u32 = 1;
pub const VECTOR_SCALE_DENOMINATOR: u32 = 10_000;
pub const CENTROIDS_DIM_MAJOR: u32 = 1;
pub const PAD_VECTOR_LANE: i16 = std.math.maxInt(i16);
pub const LABEL_LEGIT: u8 = 0;
pub const LABEL_FRAUD: u8 = 1;

pub const LayoutInput = struct {
    vector_count: u32,
    centroid_count: u32 = DEFAULT_CENTROID_COUNT,
    block_count: u32,
    padded_count: u32,
    fraud_count: u32,
    legit_count: u32,
    iterations: u32,
    seed: u64,
};

pub const Layout = struct {
    header_size: u32,
    vector_count: u32,
    padded_count: u32,
    block_count: u32,
    dimensions: u32,
    centroid_count: u32,
    block_width: u32,
    iterations: u32,
    seed: u64,
    centroids_offset: u64,
    list_offsets_offset: u64,
    list_sizes_offset: u64,
    vectors_offset: u64,
    labels_offset: u64,
    file_size: u64,
    fraud_count: u32,
    legit_count: u32,
    vector_encoding: u32,
    vector_scale_denominator: u32,
    centroid_layout: u32,
};

pub fn layoutFor(input: LayoutInput) !Layout {
    if (input.vector_count == 0) return error.EmptyReferenceSet;
    if (input.centroid_count == 0) return error.InvalidCentroidCount;
    if (input.block_count == 0) return error.InvalidBlockCount;
    if (input.padded_count != input.block_count * BLOCK_WIDTH) return error.InvalidPadding;
    if (input.fraud_count + input.legit_count != input.vector_count) return error.InvalidLabelCounts;

    var offset: u64 = @intCast(HEADER_SIZE);
    const centroids_offset = offset;
    offset += @as(u64, input.centroid_count) * DIMENSIONS * @sizeOf(f32);
    const list_offsets_offset = offset;
    offset += @as(u64, input.centroid_count + 1) * @sizeOf(u32);
    const list_sizes_offset = offset;
    offset += @as(u64, input.centroid_count) * @sizeOf(u32);
    const vectors_offset = offset;
    offset += @as(u64, input.block_count) * BLOCK_LANES * @sizeOf(i16);
    const labels_offset = offset;
    offset += @as(u64, input.padded_count) * @sizeOf(u8);

    return .{
        .header_size = @intCast(HEADER_SIZE),
        .vector_count = input.vector_count,
        .padded_count = input.padded_count,
        .block_count = input.block_count,
        .dimensions = DIMENSIONS,
        .centroid_count = input.centroid_count,
        .block_width = BLOCK_WIDTH,
        .iterations = input.iterations,
        .seed = input.seed,
        .centroids_offset = centroids_offset,
        .list_offsets_offset = list_offsets_offset,
        .list_sizes_offset = list_sizes_offset,
        .vectors_offset = vectors_offset,
        .labels_offset = labels_offset,
        .file_size = offset,
        .fraud_count = input.fraud_count,
        .legit_count = input.legit_count,
        .vector_encoding = VECTOR_ENCODING_I16_Q10000,
        .vector_scale_denominator = VECTOR_SCALE_DENOMINATOR,
        .centroid_layout = CENTROIDS_DIM_MAJOR,
    };
}

pub fn encodeHeader(layout: Layout) [HEADER_SIZE]u8 {
    var out = [_]u8{0} ** HEADER_SIZE;
    @memcpy(out[0..8], &MAGIC);
    writeU32(&out, 8, VERSION);
    writeU32(&out, 12, layout.header_size);
    writeU32(&out, 16, layout.vector_count);
    writeU32(&out, 20, layout.padded_count);
    writeU32(&out, 24, layout.block_count);
    writeU32(&out, 28, layout.dimensions);
    writeU32(&out, 32, layout.centroid_count);
    writeU32(&out, 36, layout.block_width);
    writeU32(&out, 40, layout.iterations);
    writeU64(&out, 48, layout.seed);
    writeU64(&out, 56, layout.centroids_offset);
    writeU64(&out, 64, layout.list_offsets_offset);
    writeU64(&out, 72, layout.list_sizes_offset);
    writeU64(&out, 80, layout.vectors_offset);
    writeU64(&out, 88, layout.labels_offset);
    writeU64(&out, 96, layout.file_size);
    writeU32(&out, 104, layout.fraud_count);
    writeU32(&out, 108, layout.legit_count);
    writeU32(&out, 112, layout.vector_encoding);
    writeU32(&out, 116, layout.vector_scale_denominator);
    writeU32(&out, 120, layout.centroid_layout);
    return out;
}

pub fn decodeHeader(bytes: *const [HEADER_SIZE]u8) !Layout {
    if (!std.mem.eql(u8, bytes[0..8], &MAGIC)) return error.BadMagic;
    if (readU32(bytes, 8) != VERSION) return error.BadVersion;

    return .{
        .header_size = readU32(bytes, 12),
        .vector_count = readU32(bytes, 16),
        .padded_count = readU32(bytes, 20),
        .block_count = readU32(bytes, 24),
        .dimensions = readU32(bytes, 28),
        .centroid_count = readU32(bytes, 32),
        .block_width = readU32(bytes, 36),
        .iterations = readU32(bytes, 40),
        .seed = readU64(bytes, 48),
        .centroids_offset = readU64(bytes, 56),
        .list_offsets_offset = readU64(bytes, 64),
        .list_sizes_offset = readU64(bytes, 72),
        .vectors_offset = readU64(bytes, 80),
        .labels_offset = readU64(bytes, 88),
        .file_size = readU64(bytes, 96),
        .fraud_count = readU32(bytes, 104),
        .legit_count = readU32(bytes, 108),
        .vector_encoding = readU32(bytes, 112),
        .vector_scale_denominator = readU32(bytes, 116),
        .centroid_layout = readU32(bytes, 120),
    };
}

fn writeU32(buf: *[HEADER_SIZE]u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, buf[offset..][0..4], value, .little);
}

fn writeU64(buf: *[HEADER_SIZE]u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, buf[offset..][0..8], value, .little);
}

fn readU32(buf: *const [HEADER_SIZE]u8, offset: usize) u32 {
    return std.mem.readInt(u32, buf[offset..][0..4], .little);
}

fn readU64(buf: *const [HEADER_SIZE]u8, offset: usize) u64 {
    return std.mem.readInt(u64, buf[offset..][0..8], .little);
}
