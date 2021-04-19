const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("odbc", "src/lib.zig");
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.linkSystemLibrary("odbc32");
    lib.install();

    var types_test = b.addTest("src/types.zig");
    types_test.setBuildMode(mode);
    types_test.setTarget(target);
    types_test.linkLibC();
    types_test.linkSystemLibrary("odbc32");

    const test_cmd = b.step("test", "Run library tests");
    test_cmd.dependOn(&types_test.step);
}
