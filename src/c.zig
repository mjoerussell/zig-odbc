const builtin = @import("std").builtin;

const c_decls =  if (builtin.os.tag == .windows)
    @cImport({
        @cDefine("__MSABI_LONG(x)", "(long)(x)");
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
    });

const extra_decls = if (builtin.os.tag == .windows)
    struct {
        pub const SQL_OV_ODBC3_80 = 380;
        pub const SQL_CP_DRIVER_AWARE = 3;
        pub const SQL_PARAM_DATA_AVAILABLE = 101;
    }
else
    struct {
        pub const SQL_CP_DRIVER_AWARE = 3;
        pub const SQL_ATTR_ASYNC_DBC_EVENT = 119;
    };

pub usingnamespace c_decls;
pub usingnamespace extra_decls;