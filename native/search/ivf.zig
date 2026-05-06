const index_format = @import("../index/format.zig");
const index_mmap = @import("../index/mmap.zig");
const candidate_distance = @import("../vector/candidate_distance.zig");
const centroid_distance = @import("../vector/centroid_distance.zig");
const vector_types = @import("../vector/types.zig");
const topk = @import("topk.zig");
const build_options = @import("build_options");

pub const FAST_NPROBE: usize = @as(usize, build_options.fast_nprobe);
pub const FULL_NPROBE: usize = @as(usize, build_options.full_nprobe);
const MAX_PROBE: usize = @max(FAST_NPROBE, FULL_NPROBE);
const MAX_CENTROIDS: usize = @intCast(index_format.DEFAULT_CENTROID_COUNT);
const WORST_DISTANCE: f32 = 1.0e30;

pub fn countFraudIvf(query: *const vector_types.Vector14, index: *const index_mmap.IndexView) u8 {
    const centroid_count: usize = @intCast(index.layout.centroid_count);
    var centroid_distances: [MAX_CENTROIDS]f32 = undefined;
    centroid_distance.centroidDistances(query, index.centroids_dim_major, index.layout.centroid_count, centroid_distances[0..centroid_count]);

    var fast_probes = [_]u16{0} ** FAST_NPROBE;
    const fast_count = @min(centroid_count, FAST_NPROBE);
    selectTopFromDistances(centroid_distances[0..centroid_count], fast_probes[0..fast_count]);

    const preliminary = scanProbeLists(query, index, fast_probes[0..fast_count]);
    if (preliminary != 2 and preliminary != 3) {
        return preliminary;
    }

    var full_probes = [_]u16{0} ** FULL_NPROBE;
    const full_count = @min(centroid_count, FULL_NPROBE);
    selectTopFromDistances(centroid_distances[0..centroid_count], full_probes[0..full_count]);
    return scanProbeLists(query, index, full_probes[0..full_count]);
}

fn selectTopFromDistances(distances: []const f32, out: []u16) void {
    if (out.len == 0) return;

    var top_dists = [_]f32{WORST_DISTANCE} ** MAX_PROBE;
    var top_idx = [_]u16{0} ** MAX_PROBE;
    for (distances, 0..) |distance, ci| {
        if (distance >= top_dists[out.len - 1]) continue;
        var pos = out.len - 1;
        while (pos > 0 and distance < top_dists[pos - 1]) : (pos -= 1) {
            top_dists[pos] = top_dists[pos - 1];
            top_idx[pos] = top_idx[pos - 1];
        }
        top_dists[pos] = distance;
        top_idx[pos] = @intCast(ci);
    }
    @memcpy(out, top_idx[0..out.len]);
}

fn scanProbeLists(
    query: *const vector_types.Vector14,
    index: *const index_mmap.IndexView,
    probes: []const u16,
) u8 {
    var top = topk.Top5.init();

    for (probes) |cell| {
        scanList(query, index, cell, &top);
    }

    return top.fraudCount();
}

fn scanList(
    query: *const vector_types.Vector14,
    index: *const index_mmap.IndexView,
    cell: u16,
    top: *topk.Top5,
) void {
    const cell_index: usize = @intCast(cell);
    const start_block = index.list_offsets[cell_index];
    const size = index.list_sizes[cell_index];
    var seen: u32 = 0;
    while (seen < size) {
        const global_block = start_block + seen / index_format.BLOCK_WIDTH;
        const slot_count = @min(index_format.BLOCK_WIDTH, size - seen);
        var slot: u32 = 0;
        while (slot < slot_count) : (slot += 1) {
            const distance = candidate_distance.distanceBlockSlotBounded(query, index.vector_blocks, global_block, slot, top.worstDistance());
            const label_index: usize = @intCast(global_block * index_format.BLOCK_WIDTH + slot);
            top.insert(distance, index.labels[label_index]);
        }
        seen += slot_count;
    }
}
