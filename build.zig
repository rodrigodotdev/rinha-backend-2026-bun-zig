const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fast_nprobe = b.option(u16, "fast-nprobe", "Number of IVF lists for first pass") orelse 10;
    const full_nprobe = b.option(u16, "full-nprobe", "Number of IVF lists for boundary fallback") orelse 16;

    const search_options = b.addOptions();
    search_options.addOption(u16, "fast_nprobe", fast_nprobe);
    search_options.addOption(u16, "full_nprobe", full_nprobe);

    const native_module = b.createModule(.{
        .root_source_file = b.path("native/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_module.addOptions("build_options", search_options);

    const lib = b.addLibrary(.{
        .name = "fraud",
        .linkage = .dynamic,
        .root_module = native_module,
    });

    b.installArtifact(lib);

    const prepare_module = b.createModule(.{
        .root_source_file = b.path("native/prepare/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    prepare_module.addImport("index_format", b.createModule(.{
        .root_source_file = b.path("native/index/format.zig"),
        .target = target,
        .optimize = optimize,
    }));
    prepare_module.addImport("vector_types", b.createModule(.{
        .root_source_file = b.path("native/vector/types.zig"),
        .target = target,
        .optimize = optimize,
    }));

    const prepare_index = b.addExecutable(.{
        .name = "prepare-index",
        .root_module = prepare_module,
    });

    const run_prepare_index = b.addRunArtifact(prepare_index);
    if (b.args) |args| {
        run_prepare_index.addArgs(args);
    }

    const build_index_step = b.step("build-index", "Build fraud-index.bin from references.json or references.json.gz");
    build_index_step.dependOn(&run_prepare_index.step);
}
