const std = @import("std");
const references = @import("references.zig");
const kmeans = @import("kmeans.zig");
const writer = @import("writer.zig");
const index_format = @import("index_format");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    const input_path = args.next() orelse {
        printUsage();
        return error.InvalidArgs;
    };
    const output_path = args.next() orelse {
        printUsage();
        return error.InvalidArgs;
    };

    var option_args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer option_args.deinit(allocator);
    while (args.next()) |arg| try option_args.append(allocator, arg);
    const options = try parseOptions(option_args.items);

    std.debug.print("[prepare] input={s} output={s} k={d} iterations={d} sample={d} seed={d}\n", .{
        input_path,
        output_path,
        options.centroid_count,
        options.iterations,
        options.sample_limit,
        options.seed,
    });

    var refs = try readReferences(io, allocator, input_path);
    defer refs.deinit(allocator);
    std.debug.print("[prepare] read refs={d} fraud={d} legit={d}\n", .{ refs.vectors.len, refs.fraud_count, refs.legit_count });

    var training = try kmeans.trainAndAssign(allocator, refs.vectors, options);
    defer training.deinit(allocator);

    var built = try writer.build(
        allocator,
        refs.vectors,
        refs.labels,
        training.assignments,
        training.centroids,
        options.centroid_count,
    );
    defer built.deinit(allocator);

    const stats = listStats(built.list_sizes);
    const average = @as(f64, @floatFromInt(refs.vectors.len)) / @as(f64, @floatFromInt(options.centroid_count));
    std.debug.print("[prepare] lists non_empty={d} min={d} max={d} avg={d:.2}\n", .{
        stats.non_empty,
        stats.min,
        stats.max,
        average,
    });

    const layout = try index_format.layoutFor(.{
        .vector_count = @intCast(refs.vectors.len),
        .centroid_count = options.centroid_count,
        .block_count = built.block_count,
        .padded_count = built.padded_count,
        .fraud_count = refs.fraud_count,
        .legit_count = refs.legit_count,
        .iterations = options.iterations,
        .seed = options.seed,
    });

    try writer.writeBinaryPathIo(io, std.Io.Dir.cwd(), output_path, layout, &built);

    std.debug.print("[prepare] wrote bytes={d} blocks={d} padded={d} max_list={d}\n", .{
        layout.file_size,
        built.block_count,
        built.padded_count,
        built.max_list_size,
    });
}

fn printUsage() void {
    std.debug.print("usage: build-index -- <input.json|input.json.gz> <output.bin> [--k N] [--iterations N] [--sample N] [--seed N]\n", .{});
}

pub fn parseOptions(args: []const []const u8) !kmeans.Options {
    var options = kmeans.Options{};
    var index: usize = 0;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len) return error.MissingOptionValue;
        const name = args[index];
        const value = args[index + 1];

        if (std.mem.eql(u8, name, "--k")) {
            options.centroid_count = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--iterations")) {
            options.iterations = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--sample")) {
            options.sample_limit = try std.fmt.parseInt(u32, value, 0);
        } else if (std.mem.eql(u8, name, "--seed")) {
            options.seed = try std.fmt.parseInt(u64, value, 0);
        } else {
            return error.UnknownOption;
        }
    }
    return options;
}

fn readReferences(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !references.ReferenceSet {
    if (std.mem.endsWith(u8, path, ".gz")) {
        const file = try std.Io.Dir.cwd().openFile(io, path, .{});
        defer file.close(io);

        var file_buffer: [64 * 1024]u8 = undefined;
        var file_reader = file.readerStreaming(io, &file_buffer);
        var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        var gzip = std.compress.flate.Decompress.init(&file_reader.interface, .gzip, &decompress_buffer);
        var json_reader = std.json.Reader.init(allocator, &gzip.reader);
        defer json_reader.deinit();
        return references.parseTokenSource(allocator, &json_reader);
    }

    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(input);
    return references.parseSlice(allocator, input);
}

const ListStats = struct {
    non_empty: u32,
    min: u32,
    max: u32,
};

fn listStats(list_sizes: []const u32) ListStats {
    var non_empty: u32 = 0;
    var min: u32 = std.math.maxInt(u32);
    var max: u32 = 0;
    for (list_sizes) |size| {
        if (size != 0) non_empty += 1;
        if (size < min) min = size;
        if (size > max) max = size;
    }
    if (list_sizes.len == 0) min = 0;
    return .{ .non_empty = non_empty, .min = min, .max = max };
}
