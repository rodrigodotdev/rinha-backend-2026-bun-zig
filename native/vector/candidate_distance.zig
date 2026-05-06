const vector_types = @import("types.zig");
const index_format = @import("../index/format.zig");

const VECTOR_SCALE: f32 = 0.0001;
const BLOCK_WIDTH_USIZE: usize = @intCast(index_format.BLOCK_WIDTH);

fn decodeLane(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) * VECTOR_SCALE;
}

pub fn distanceBlockSlotBounded(
    query: *const vector_types.Vector14,
    blocks: []const i16,
    global_block: u32,
    slot: u32,
    limit: f32,
) f32 {
    const block_origin = @as(usize, @intCast(global_block)) * index_format.BLOCK_LANES;
    const slot_index: usize = @intCast(slot);
    var total: f32 = 0.0;
    inline for (0..14) |dim| {
        const lane = block_origin + dim * BLOCK_WIDTH_USIZE + slot_index;
        const delta = decodeLane(blocks[lane]) - query[dim];
        total += delta * delta;
        if (total >= limit) return total;
    }
    return total;
}
