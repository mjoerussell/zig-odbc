const std = @import("std");
const builtin = std.builtin;
const Builder = std.build.Builder;

const test_files = .{ "src/types.zig", "src/util.zig" };

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("odbc", "src/lib.zig");
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.linkLibC();

    const odbc_library_name = if (builtin.os.tag == .windows) "odbc32" else "odbc";
    
    if (builtin.os.tag == .macos) {
        lib.addIncludeDir("/usr/local/include");
        lib.addIncludeDir("/usr/local/Cellar/unixodbc/2.3.9");
    }

    lib.linkSystemLibrary(odbc_library_name);
    lib.install();

    const test_cmd = b.step("test", "Run library tests");
    inline for (test_files) |filename| {
        var file_tests = b.addTest(filename);
        file_tests.setBuildMode(mode);
        file_tests.setTarget(target);
        file_tests.linkLibC();

        if (builtin.os.tag == .macos) {
            file_tests.addIncludeDir("/usr/local/include");
            file_tests.addIncludeDir("/usr/local/Cellar/unixodbc/2.3.9");
        }

        file_tests.linkSystemLibrary(odbc_library_name);
        test_cmd.dependOn(&file_tests.step);
    }

}
