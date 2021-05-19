// const std = @import("std");
const builtin = @import("std").builtin;

const c_decls =  if (builtin.os.tag == .windows)
        @cImport({
            @cInclude("windows.h");
            @cInclude("sql.h");
            @cInclude("sqltypes.h");
            @cInclude("sqlext.h");
        })
    else
        @cImport({
            @cInclude("sql.h");
            @cInclude("sqltypes.h");
            @cInclude("sqlext.h");
            @cDefine("SQL_CP_DRIVER_AWARE", 3);
        });

pub usingnamespace c_decls;