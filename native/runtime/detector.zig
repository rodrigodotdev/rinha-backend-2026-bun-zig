const std = @import("std");
const index_mmap = @import("../index/mmap.zig");
const ivf_search = @import("../search/ivf.zig");
const vector_types = @import("../vector/types.zig");

const StateTag = enum {
    empty,
    ready,
    failed,
};

const State = struct {
    tag: StateTag = .empty,
    threaded: ?std.Io.Threaded = null,
    mapped: ?index_mmap.MappedIndex = null,
};

var state: State = .{};

pub fn initDefault() i32 {
    deinit();
    state.threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
    const io = state.threaded.?.io();
    state.mapped = index_mmap.loadDefault(io) catch |err| {
        std.debug.print("[fraud] index load failed: {s}\n", .{@errorName(err)});
        state.threaded.?.deinit();
        state.threaded = null;
        state.tag = .failed;
        return -1;
    };
    state.tag = .ready;
    std.debug.print("[fraud] loaded index refs={d} k={d} bytes={d}\n", .{
        state.mapped.?.view.layout.vector_count,
        state.mapped.?.view.layout.centroid_count,
        state.mapped.?.view.layout.file_size,
    });
    return 0;
}

pub fn ready() bool {
    return state.tag == .ready;
}

pub fn countFraud(query: *const vector_types.Vector14) u8 {
    if (state.tag != .ready) return 0;
    if (state.mapped) |*mapped| {
        return ivf_search.countFraudIvf(query, &mapped.view);
    }
    return 0;
}

fn deinit() void {
    if (state.threaded) |*threaded| {
        const io = threaded.io();
        if (state.mapped) |*mapped| mapped.deinit(io);
        state.mapped = null;
        threaded.deinit();
        state.threaded = null;
    }
    state.tag = .empty;
}
