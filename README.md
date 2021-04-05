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

## Example Application

This example connects to a database, sets and gets some attributes, and creates a table using `Statement.executeDirect`.

```zig
const std = @import("std");
const odbc = @import("odbc");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    // Step 1: Create an Environment
    var environment = try odbc.Environment.init(allocator);
    defer environment.deinit() catch |err| {};

    // Step 2: Set the ODBC version
    try environment.setOdbcVersion(.Odbc3);
    const version = try environment.getOdbcVersion();
    std.debug.print("Version is {s}\n", .{@tagName(version)});

    // Step 3: Initialize a Connection
    var connection = try odbc.Connection.init(allocator, &environment);
    defer connection.deinit() catch |err| {};

    // Optionally set connection attributes
    connection.setAttribute(.{ .LoginTimeout = 1000 }) catch |err| {
        const errors = try connection.getErrors(connection.allocator);
        defer allocator.free(errors);
        for (errors) |e| {
            std.debug.print("Set Attribute Error: {s}\n", .{@tagName(e)});
        }
    };

    const default_login_timeout = try connection.getAttribute(.LoginTimeout);
    std.debug.print("Current login timeout = {}\n", .{default_login_timeout.?.LoginTimeout});

    // Step 4: Connect to a database using a connection string
    connection.connectExtended("ODBC;driver=PostgreSQL Unicode(x64);DSN=PostgreSQL35W", .NoPrompt) catch |err| {
        const errors = try connection.getErrors(allocator);
        defer allocator.free(errors);
        for (errors) |e| {
            std.debug.print("Connection error: {s}\n", .{@tagName(e)});
        }
    };

    std.debug.print("Connected\n", .{});

    // Optionally get some info about the connection
    const enabled_funcs = try connection.getAllEnabledFunctions();
    defer connection.allocator.free(enabled_funcs);

    std.debug.print("Enabled functions: ", .{});
    for (enabled_funcs) |func| {
        std.debug.print("{s} ", .{@tagName(func)});
    }
    std.debug.print("\n", .{});

    const tx = try connection.getInfo(.ConvertChar);
    std.debug.print("Transaction Capable: {}\n", .{tx});

    // Step 5: Initialize a statement
    var statement = try odbc.Statement.init(&connection, allocator);
    defer statement.deinit() catch |_| {};

    // Optionally get/set statement attributes
    statement.setAttribute(.{ .QueryTimeout = 2201 }) catch |err| {
        const errors = try statement.getErrors(allocator);
        defer allocator.free(errors);

        for (errors) |e| {
            std.debug.print("Statement set attribute error: {s}\n", .{@tagName(e)});
        }
    };

    const query_timeout = try statement.getAttribute(.QueryTimeout);
    std.debug.print("Query Timeout is {}\n", .{query_timeout.QueryTimeout});

    _ = statement.getColumnAttribute(1, .AutoUniqueValue) catch |err| {
        const errors = try statement.getErrors(allocator);
        defer allocator.free(errors);

        for (errors) |e| {
            std.debug.print("Exptected error, got {s}\n", .{@tagName(e)});
        }
    };

    // A very simplistic example of binding buffers to a result set, using `Statement.tables` as the data source
    var catalog_col_buf: [1024]u8 = undefined;
    var catalog_col_ind: c_longlong = undefined;
    var schema_col_buf: [1024]u8 = undefined;
    var schema_col_ind: c_longlong = undefined;
    var table_name_col_buf: [1024]u8 = undefined;
    var table_name_col_ind: c_longlong = undefined;
    var table_type_col_buf: [1024]u8 = undefined;
    var table_type_col_ind: c_longlong = undefined;
    var remarks_col_buf: [1024]u8 = undefined;
    var remarks_col_ind: c_longlong = undefined;

    try statement.bindColumn(1, odbc.Types.CType.Char, catalog_col_buf[0..], &catalog_col_ind);
    try statement.bindColumn(2, odbc.Types.CType.Char, schema_col_buf[0..], &schema_col_ind);
    try statement.bindColumn(3, odbc.Types.CType.Char, table_name_col_buf[0..], &table_name_col_ind);
    try statement.bindColumn(4, odbc.Types.CType.Char, table_type_col_buf[0..], &table_type_col_ind);
    try statement.bindColumn(5, odbc.Types.CType.Char, remarks_col_buf[0..], &remarks_col_ind);

    try statement.tables("zig-test", "public", "%", "%");

    while (true) {
        if (statement.fetch()) {
            if (catalog_col_ind != odbc.sys.SQL_NULL_DATA) {
                std.debug.print("Catalog: {s}\n", .{catalog_col_buf[0..@intCast(usize, catalog_col_ind)]});
            }
            if (schema_col_ind != odbc.sys.SQL_NULL_DATA) {
                std.debug.print("Schema: {s}\n", .{schema_col_buf[0..@intCast(usize, schema_col_ind)]});
            }
            if (table_name_col_ind != odbc.sys.SQL_NULL_DATA) {
                std.debug.print("Table Name: {s}\n", .{table_name_col_buf[0..@intCast(usize, table_name_col_ind)]});
            }
            if (table_type_col_ind != odbc.sys.SQL_NULL_DATA) {
                std.debug.print("Table Type: {s}\n", .{table_type_col_buf[0..@intCast(usize, table_type_col_ind)]});
            }
            if (remarks_col_ind != odbc.sys.SQL_NULL_DATA) {
                std.debug.print("Remarks: {s}\n", .{remarks_col_buf[0..@intCast(usize, remarks_col_ind)]});
            }
        } else |err| {
            switch (err) {
                error.NoData => {
                    std.debug.print("No data available\n", .{});
                    break;
                },
                error.StillExecuting => continue,
                else => break
            }
        }
    }

    // Execute a SQL statement
    const create_table_result = statement.executeDirect(
        \\CREATE TABLE IF NOT EXISTS odbc_zig_test (
        \\  id serial PRIMARY KEY,
        \\  name VARCHAR(100) NOT NULL,
        \\  occupation VARCHAR(100),
        \\  age INT DEFAULT 18
        \\)
    ) catch |err| {
        var error_buffer: [@sizeOf(odbc.Error.SqlState) * 5]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(error_buffer[0..]);
        const errors = try statement.getErrors(&fba.allocator);
        for (errors) |e| {
            std.debug.print("Execute Error: {s}\n", .{@tagName(e)});
        }
        return err;
    }
    std.debug.print("Execute result: {s}\n", .{@tagName(create_table_result)});
}
```
