# Zig ODBC Bindings

Idiomatic Zig bindings for the ODBC driver interface. This is meant to be a low-level building block for ODBC interfaces or applications. It can be used directly
to interface with a database, or it can be used to build more sophisticated connection management libraries.

## How To Use

After adding this package to your codebase, update your `build.zig` to include the highlighted lines:

```zig
pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("odbc-test", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    // ODBC configuration
    exe.addPackagePath("odbc", "odbc/src/lib.zig"); // <-- Add the main lib.zig as a package
    exe.linkLibC(); // <-- Link libc
    exe.linkSystemLibrary("odbc32"); // <-- Link the ODBC system library
    // End ODBC configuration

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```
