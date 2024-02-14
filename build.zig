const std = @import("std");
const Allocator = std.mem.Allocator;

const builtin = @import("builtin");
const Build = std.Build;

const TestItem = struct {
    name: []const u8,
    source_file: std.Build.LazyPath,
};

const test_files = [_]TestItem{
    .{
        .name = "types",
        .source_file = .{ .path = "src/types.zig" },
    },
    .{
        .name = "util",
        .source_file = .{ .path = "src/util.zig" },
    },
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "odbc",
        .target = target,
        .optimize = optimize,
    });

    setupOdbcDependencies(lib);
    b.installArtifact(lib);

    _ = b.addModule("zig-odbc", .{
        .root_source_file = .{ .path = "src/lib.zig" },
    });

    const test_cmd = b.step("test", "Run library tests");

    var tests: [test_files.len]*std.Build.Step.Compile = undefined;
    inline for (test_files, 0..) |item, index| {
        const current_tests = b.addTest(.{
            .name = item.name,
            .root_source_file = item.source_file,
            .optimize = optimize,
            .target = target,
        });

        setupOdbcDependencies(current_tests);

        tests[index] = current_tests;
    }
    for (tests) |t| {
        test_cmd.dependOn(&t.step);
    }
}

pub fn setupOdbcDependencies(step: *std.Build.Step.Compile) void {
    step.linkLibC();

    const odbc_library_name = if (builtin.os.tag == .windows) "odbc32" else "odbc";
    if (builtin.os.tag == .macos) {
        step.addIncludeDir("/usr/local/include");
        step.addIncludeDir("/usr/local/lib");
    }

    step.linkSystemLibrary(odbc_library_name);
}
