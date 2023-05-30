const std = @import("std");
const builtin = @import("builtin");
const CompileStep = std.build.CompileStep;

pub const odbc_library_name = if (builtin.os.tag == .windows) "odbc32" else "odbc";

pub fn buildPkg(exe: *CompileStep, package_name: []const u8) void {
    addOdbcLibraries(exe);
    exe.addAnonymousModule(package_name, .{
        .source_file = .{ .path = "zig-odbc/src/lib.zig" },
    });
}

pub fn addOdbcLibraries(exe: *CompileStep) void {
    exe.linkLibC();

    if (builtin.os.tag == .macos) {
        exe.addIncludeDir("/usr/local/include");
        exe.addIncludeDir("/usr/local/lib");
    }

    exe.linkSystemLibrary(odbc_library_name);
}
