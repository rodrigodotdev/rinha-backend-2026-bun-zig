const std = @import("std");
const vector_types = @import("vector_types");
const index_format = @import("index_format");

pub const Options = struct {
    centroid_count: u32 = index_format.DEFAULT_CENTROID_COUNT,
    iterations: u32 = 25,
    seed: u64 = 0xdeadbeefcafebabe,
    sample_limit: u32 = 262_144,
};

pub const Result = struct {
    centroids: []vector_types.Vector14,
    assignments: []u16,
    iterations: u32,
    seed: u64,
    sampled_count: u32,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        allocator.free(self.centroids);
        allocator.free(self.assignments);
        self.* = .{ .centroids = &.{}, .assignments = &.{}, .iterations = 0, .seed = 0, .sampled_count = 0 };
    }
};

pub fn trainAndAssign(allocator: std.mem.Allocator, vectors: []const vector_types.Vector14, options: Options) !Result {
    if (vectors.len == 0) return error.EmptyReferenceSet;
    if (options.centroid_count == 0 or options.centroid_count > vectors.len) return error.InvalidCentroidCount;
    if (options.centroid_count > std.math.maxInt(u16)) return error.CentroidCountTooLarge;

    const sampled_count: u32 = @min(@as(u32, @intCast(vectors.len)), options.sample_limit);
    if (sampled_count < options.centroid_count) return error.InvalidSampleLimit;

    const sample_indices = try buildSample(allocator, vectors.len, sampled_count, options.seed);
    defer allocator.free(sample_indices);

    const centroids = try initKMeansPlusPlus(allocator, vectors, sample_indices, options.centroid_count, options.seed);
    errdefer allocator.free(centroids);

    const sample_assignments = try allocator.alloc(u16, sample_indices.len);
    defer allocator.free(sample_assignments);
    @memset(sample_assignments, std.math.maxInt(u16));

    var completed_iterations: u32 = 0;
    while (completed_iterations < options.iterations) : (completed_iterations += 1) {
        const changed = assignSample(vectors, sample_indices, centroids, sample_assignments);
        try updateCentroids(allocator, vectors, sample_indices, sample_assignments, centroids);
        std.debug.print("[kmeans] iter {d}/{d} sample={d} k={d} changed={d}\n", .{
            completed_iterations + 1,
            options.iterations,
            sampled_count,
            options.centroid_count,
            changed,
        });
        if (changed * 1000 < sample_indices.len) {
            completed_iterations += 1;
            break;
        }
    }

    const assignments = try allocator.alloc(u16, vectors.len);
    errdefer allocator.free(assignments);
    assignAll(vectors, centroids, assignments);

    return .{
        .centroids = centroids,
        .assignments = assignments,
        .iterations = completed_iterations,
        .seed = options.seed,
        .sampled_count = sampled_count,
    };
}

fn buildSample(allocator: std.mem.Allocator, vector_count: usize, sampled_count: u32, seed: u64) ![]u32 {
    var sample = try allocator.alloc(u32, sampled_count);
    if (sampled_count == vector_count) {
        for (sample, 0..) |*slot, index| slot.* = @intCast(index);
        return sample;
    }

    for (sample, 0..) |*slot, index| slot.* = @intCast(index);

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var index: usize = sampled_count;
    while (index < vector_count) : (index += 1) {
        const chosen = random.uintLessThan(usize, index + 1);
        if (chosen < sampled_count) sample[chosen] = @intCast(index);
    }

    return sample;
}

fn initKMeansPlusPlus(
    allocator: std.mem.Allocator,
    vectors: []const vector_types.Vector14,
    sample_indices: []const u32,
    centroid_count: u32,
    seed: u64,
) ![]vector_types.Vector14 {
    var centroids = try allocator.alloc(vector_types.Vector14, centroid_count);
    errdefer allocator.free(centroids);

    var nearest_distances = try allocator.alloc(f32, sample_indices.len);
    defer allocator.free(nearest_distances);
    @memset(nearest_distances, std.math.floatMax(f32));

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    const first_index = random.uintLessThan(usize, sample_indices.len);
    centroids[0] = vectors[sample_indices[first_index]];

    var centroid_index: usize = 1;
    while (centroid_index < centroid_count) : (centroid_index += 1) {
        var total: f64 = 0.0;
        const previous = &centroids[centroid_index - 1];
        for (sample_indices, 0..) |row, sample_index| {
            const distance = distanceSquared(&vectors[row], previous);
            if (distance < nearest_distances[sample_index]) nearest_distances[sample_index] = distance;
            total += nearest_distances[sample_index];
        }

        if (total <= 0.0) {
            centroids[centroid_index] = vectors[sample_indices[centroid_index % sample_indices.len]];
            continue;
        }

        const target = random.float(f64) * total;
        var cumulative: f64 = 0.0;
        var chosen_index: usize = sample_indices.len - 1;
        for (nearest_distances, 0..) |distance, sample_index| {
            cumulative += distance;
            if (cumulative >= target) {
                chosen_index = sample_index;
                break;
            }
        }

        centroids[centroid_index] = vectors[sample_indices[chosen_index]];
    }

    return centroids;
}

fn assignSample(
    vectors: []const vector_types.Vector14,
    sample_indices: []const u32,
    centroids: []const vector_types.Vector14,
    assignments: []u16,
) u32 {
    var changed: u32 = 0;
    for (sample_indices, 0..) |row, index| {
        const next = closestCentroid(&vectors[row], centroids);
        if (assignments[index] != next) {
            assignments[index] = next;
            changed += 1;
        }
    }
    return changed;
}

fn updateCentroids(
    allocator: std.mem.Allocator,
    vectors: []const vector_types.Vector14,
    sample_indices: []const u32,
    assignments: []const u16,
    centroids: []vector_types.Vector14,
) !void {
    const centroid_count = centroids.len;
    var sums = try allocator.alloc(f64, centroid_count * index_format.DIMENSIONS);
    defer allocator.free(sums);
    @memset(sums, 0.0);

    var counts = try allocator.alloc(u32, centroid_count);
    defer allocator.free(counts);
    @memset(counts, 0);

    for (sample_indices, assignments) |row, cell| {
        counts[cell] += 1;
        const sum_base = @as(usize, cell) * index_format.DIMENSIONS;
        inline for (0..14) |dim| {
            sums[sum_base + dim] += vectors[row][dim];
        }
    }

    for (centroids, 0..) |*centroid, cell| {
        const count = counts[cell];
        if (count == 0) continue;
        const denominator: f64 = @floatFromInt(count);
        const sum_base = cell * index_format.DIMENSIONS;
        inline for (0..14) |dim| {
            centroid[dim] = @floatCast(sums[sum_base + dim] / denominator);
        }
    }
}

fn assignAll(vectors: []const vector_types.Vector14, centroids: []const vector_types.Vector14, assignments: []u16) void {
    for (vectors, assignments) |*vector, *assignment| {
        assignment.* = closestCentroid(vector, centroids);
    }
}

fn closestCentroid(vector: *const vector_types.Vector14, centroids: []const vector_types.Vector14) u16 {
    var best_index: u16 = 0;
    var best_distance = std.math.floatMax(f32);
    for (centroids, 0..) |*centroid, index| {
        const distance = distanceSquaredBounded(vector, centroid, best_distance);
        if (distance < best_distance) {
            best_distance = distance;
            best_index = @intCast(index);
        }
    }
    return best_index;
}

fn distanceSquaredBounded(a: *const vector_types.Vector14, b: *const vector_types.Vector14, limit: f32) f32 {
    var total: f32 = 0.0;
    inline for (0..14) |index| {
        const delta = a[index] - b[index];
        total += delta * delta;
        if (total >= limit) return total;
    }
    return total;
}

fn distanceSquared(a: *const vector_types.Vector14, b: *const vector_types.Vector14) f32 {
    var total: f32 = 0.0;
    inline for (0..14) |index| {
        const delta = a[index] - b[index];
        total += delta * delta;
    }
    return total;
}
