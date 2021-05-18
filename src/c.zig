// const std = @import("std");
const builtin = @import("std").builtin;

const is_windows = comptime builtin.os.tag == .windows;

pub usingnamespace if (is_windows)
    @cImport({
        @cInclude("windows.h");
        @cInclude("sql.h");
        @cInclude("sqltypes.h");
        @cInclude("sqlext.h");
    })
else
    struct {
        pub usingnamespace @cImport({
            @cInclude("sql.h");
            @cInclude("sqltypes.h");
            @cInclude("sqlext.h");
        });

        pub const SQL_CP_DRIVER_AWARE = 3;

    };