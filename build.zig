const version = @import("builtin").zig_version;
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_step = b.step("test", "Run unit tests");

    const zigRocksDb = b.addStaticLibrary(.{ .name = "rocksdb", .root_source_file = .{ .path = "rocksdb.zig" }, .target = target, .optimize = optimize });
    zigRocksDb.linkLibC();

    const unit_tests = b.addTest(.{ .root_source_file = .{ .path = b.pathFromRoot("rocksdb.zig") }, .target = target, .optimize = optimize });
    unit_tests.linkLibC();

    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    zigRocksDb.linkSystemLibrary("rocksdb");
    unit_tests.linkSystemLibrary("rocksdb");

    b.installArtifact(zigRocksDb);
}
