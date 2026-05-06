const vector_types = @import("types.zig");

const Vec8 = @Vector(8, f32);

pub fn centroidDistances(
    query: *const vector_types.Vector14,
    centroids_dim_major: []const f32,
    centroid_count: u32,
    out: []f32,
) void {
    centroidDistancesVector(query, centroids_dim_major, centroid_count, out);
}

fn centroidDistancesVector(
    query: *const vector_types.Vector14,
    centroids_dim_major: []const f32,
    centroid_count: u32,
    out: []f32,
) void {
    @setFloatMode(.optimized);

    const k: usize = @intCast(centroid_count);
    @memset(out[0..k], 0.0);

    var ci: usize = 0;
    while (ci + 8 <= k) : (ci += 8) {
        var acc: Vec8 = @splat(0.0);
        inline for (0..14) |dim| {
            const base = dim * k + ci;
            const c = loadF32x8(centroids_dim_major, base);
            const q: Vec8 = @splat(query[dim]);
            const delta = c - q;
            acc = @mulAdd(Vec8, delta, delta, acc);
        }
        storeF32x8(out, ci, acc);
    }

    while (ci < k) : (ci += 1) {
        var total: f32 = 0.0;
        inline for (0..14) |dim| {
            const delta = centroids_dim_major[dim * k + ci] - query[dim];
            total += delta * delta;
        }
        out[ci] = total;
    }
}

fn loadF32x8(values: []const f32, base: usize) Vec8 {
    var out: Vec8 = undefined;
    inline for (0..8) |lane| {
        out[lane] = values[base + lane];
    }
    return out;
}

fn storeF32x8(out: []f32, base: usize, values: Vec8) void {
    inline for (0..8) |lane| {
        out[base + lane] = values[lane];
    }
}
