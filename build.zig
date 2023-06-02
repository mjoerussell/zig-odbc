const std = @import("std");
const builtin = @import("builtin");
const build_pkg = @import("build_pkg.zig");

const odbc_library_name = build_pkg.odbc_library_name;
const addOdbcLibraries = build_pkg.addOdbcLibraries;

const Build = std.Build;

const TestItem = struct {
    name: []const u8,
    source_file: std.build.FileSource,
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

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "odbc",
        .root_source_file = .{ .path = "src/lib.zig" },
        .optimize = optimize,
        .target = target,
    });

    addOdbcLibraries(lib);
    b.installArtifact(lib);

    const test_cmd = b.step("test", "Run library tests");
    inline for (test_files) |item| {
        var file_tests = b.addTest(.{
            .name = item.name,
            .root_source_file = item.source_file,
            .optimize = optimize,
            .target = target,
        });

        file_tests.linkLibC();

        if (builtin.os.tag == .macos) {
            file_tests.addIncludeDir("/usr/local/include");
            file_tests.addIncludeDir("/usr/local/lib");
        }

        file_tests.linkSystemLibrary(odbc_library_name);
        test_cmd.dependOn(&file_tests.step);
    }
}
