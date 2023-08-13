const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("c.zig");

const Environment = @import("environment.zig").Environment;

const odbc = @import("types.zig");
const SqlReturn = odbc.SqlReturn;
const HandleType = odbc.HandleType;

const odbc_error = @import("error.zig");
const ReturnError = odbc_error.ReturnError;

pub const Connection = struct {
    pub const Attribute = odbc.ConnectionAttribute;
    pub const AttributeValue = odbc.ConnectionAttributeValue;
    pub const InformationType = odbc.InformationType;
    pub const InformationTypeValue = odbc.InformationTypeValue;

    handle: *anyopaque,

    connected: bool = false,

    pub fn init(environment: *Environment) ReturnError!Connection {
        var result: Connection = undefined;
        const alloc_result = c.SQLAllocHandle(@intFromEnum(HandleType.connection), environment.handle, @as([*c]?*anyopaque, @ptrCast(&result.handle)));
        return switch (@as(SqlReturn, @enumFromInt(alloc_result))) {
            .invalid_handle => error.InvalidHandle,
            .err => error.Error,
            else => result,
        };
    }

    /// Deinitialize the connection by disconnecting from the data source (if connected) and freeing the
    /// connection handle.
    pub fn deinit(self: *Connection) !void {
        if (self.connected) try self.disconnect();
        const result = c.SQLFreeHandle(@intFromEnum(HandleType.connection), self.handle);
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {},
            else => self.getLastError(),
        };
    }

    /// Try to connect to a data source using a username and password.
    pub fn connect(self: *Connection, server_name: []const u8, user_name: []const u8, password: []const u8) !void {
        const result = c.SQLConnect(self.handle, @as([*c]u8, @ptrFromInt(@intFromPtr(server_name.ptr))), @as(i16, @intCast(server_name.len)), @as([*c]u8, @ptrFromInt(@intFromPtr(user_name.ptr))), @as(i16, @intCast(user_name.len)), @as([*c]u8, @ptrFromInt(@intFromPtr(password.ptr))), @as(i16, @intCast(password.len)));
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {
                self.connected = true;
            },
            // @todo Async handling
            else => self.getLastError(),
        };
    }

    /// Try to connect to a data source using a connection string. Use the `completion` parameter to determine how the driver
    /// should handle missing parameters in the connection string. For most non-interactive programs, the appropriate completion
    /// type is `.NoPrompt`.
    pub fn connectExtended(self: *Connection, connection_string: []const u8, completion: odbc.DriverCompletion) !void {
        const result = c.SQLDriverConnect(self.handle, null, @as([*c]u8, @ptrFromInt(@intFromPtr(connection_string.ptr))), @as(c_short, @intCast(connection_string.len)), null, 0, null, @intFromEnum(completion));
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {
                self.connected = true;
            },
            // @todo Async handling
            else => self.getLastError(),
        };
    }

    /// `browseConnect` is intended to be called multiple times. Each time, the user can pass a connection string with some, all, or none of
    /// the parameters required to establish a connection. After the parameters are sent to the driver, a new connection string will be written
    /// to the `remaining_connection_string` buffer. This connection string will indicate the next parameters that the user or application should
    /// send to `browseConnect`.
    ///
    /// If this function runs successfully it will return the length of the next connection string. A value of `0` indicates that the connection
    /// is complete and there is no more work to be done. A value that's longer than `remaining_connection_string.len` means that the new
    /// connection string was too long to fit in the buffer. The entire buffer has been filled with as much of the string as possible, and the
    /// return value is the total, untruncated length of the full connection string.
    pub fn browseConnect(self: Connection, partial_connection_string: []const u8, remaining_connection_string: []u8) !usize {
        var out_string_len: c.SQLSMALLINT = 0;

        const result = c.SQLBrowseConnect(self.handle, @as([*]u8, @ptrFromInt(@intFromPtr(partial_connection_string.ptr))), @as(c.SQLSMALLINT, @intCast(partial_connection_string.len)), remaining_connection_string.ptr, @as(c.SQLSMALLINT, @intCast(remaining_connection_string.len)), &out_string_len);
        switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {
                // If SQLBrowseConnect returns success, then the user passed all required info and the connection should be established.
                // Set connected to true and return 0 to indicate that there is no more info needed.
                self.connected = true;
                return 0;
            },
            .needs_data => {
                if (std.mem.eql(u8, partial_connection_string, remaining_connection_string)) {
                    // If SQLBrowseConnect returns NeedsData and the out string is unchanged from the input string, that means that there are
                    // unrecoverable errors.
                    return self.getLastError();
                }
                // Otherwise, when NeedsData is returned out_string_buffer contains a connection string-like value that indicates
                // to the user what info they need to pass next
                return @as(usize, @intCast(out_string_len));
            },
            .invalid_handle => @panic("Connection.browseConnect passed invalid handle"),
            else => switch (self.getLastError()) {
                error.StringRightTrunc => {
                    return @as(usize, @intCast(out_string_len));
                },
                else => |err| return err,
            },
        }
    }

    /// Disconnect from the data source. If not connected to a data source, does nothing.
    /// `deinit` still needs to be called after this function to fully deinitialize a `Connection`.
    pub fn disconnect(self: *Connection) !void {
        if (!self.connected) return;
        const result = c.SQLDisconnect(self.handle);
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {
                self.connected = false;
            },
            // @todo Async handling
            else => self.getLastError(),
        };
    }

    /// Commit or rollback all open transactions on any statement associated with this connection.
    pub fn endTransaction(self: Connection, completion_type: odbc.CompletionType) !void {
        const result = c.SQLEndTran(@intFromEnum(HandleType.connection), self.handle, @intFromEnum(completion_type));
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {},
            .invalid_handle => @panic("Connection.endTransaction passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Cancel an in-progress function. This could be a function that returned `StillProcessing`, `NeedsData`, or
    /// a function that is actively processing on another thread.
    pub fn cancel(self: Connection) !void {
        const result = c.SQLCancelHandle(@intFromEnum(HandleType.connection), self.handle);
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {},
            .invalid_handle => @panic("Connection.cancel passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Return `true` if this driver supports the specified function, `false` otherwise. If any error occurs
    /// while running this function, returns `false`.
    pub fn isFunctionEnabled(self: Connection, function_id: odbc.FunctionId) bool {
        var supported: c.SQLUSMALLINT = 0;
        const result = c.SQLGetFunctions(self.handle, @intFromEnum(function_id), &supported);
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => supported == c.SQL_TRUE,
            else => false,
        };
    }

    /// Get all of the functions supported by this driver.
    pub fn getAllEnabledFunctions(self: Connection, allocator: Allocator) ![]odbc.FunctionId {
        var result_buffer: [c.SQL_API_ODBC3_ALL_FUNCTIONS_SIZE]c.SQLUSMALLINT = undefined;
        var result_list = std.ArrayList(odbc.FunctionId).init(allocator);
        const result = c.SQLGetFunctions(self.handle, c.SQL_API_ODBC3_ALL_FUNCTIONS, @as([*c]c_ushort, @ptrCast(&result_buffer)));
        switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {
                // Iterate over all of the function ids and check if they exist.
                inline for (@typeInfo(odbc.FunctionId).Enum.fields) |field| {
                    // Recreates the following macro:
                    // SQL_FUNC_EXISTS(pfExists,uwAPI) ((*(((UWORD*) (pfExists)) + ((uwAPI) >> 4)) & (1 << ((uwAPI) & 0x000F))) ? SQL_TRUE : SQL_FALSE)
                    const func_exists = (@intFromPtr(@as(*c_ushort, @ptrCast(&result_buffer))) + (field.value >> 4)) & (1 << (field.value & 0x000F)) != 0;
                    if (func_exists) {
                        try result_list.append(@as(odbc.FunctionId, @enumFromInt(field.value)));
                    }
                }
                return result_list.toOwnedSlice();
            },
            else => return self.getLastError(),
        }
    }

    /// Given a SQL statement, return the same statement as modified by the current driver.
    pub fn nativeSql(self: Connection, allocator: Allocator, sql_statement: []const u8) ![]const u8 {
        var out_statement_len: c.SQLINTEGER = 0;
        // Allocate a buffer for the out string, allocate the same number of chars as the in string because it's likely to be
        // close
        var out_statement_buffer = allocator.alloc(u8, sql_statement.len);
        errdefer allocator.free(out_statement_buffer);

        run_loop: while (true) {
            const result = c.SQLNativeSql(self.handle, sql_statement.ptr, sql_statement.len, out_statement_buffer.ptr, out_statement_buffer.len, &out_statement_len);
            switch (@as(SqlReturn, @enumFromInt(result))) {
                .success, .success_with_info => return out_statement_buffer,
                .invalid_handle => @panic("Connection.nativeSql passed invalid handle"),
                else => switch (self.getLastError()) {
                    error.StringRightTrunc => {
                        // If the out string was truncated, realloc to the correct length and run again
                        out_statement_buffer = try allocator.realloc(out_statement_buffer, @as(usize, @intCast(out_statement_len)) + 1);
                        continue :run_loop;
                    },
                    else => |err| return err,
                },
            }
        }
    }

    pub fn getInfo(self: Connection, comptime info_type: InformationType, allocator: Allocator) !InformationTypeValue {
        var result_buffer = try allocator.alloc(u8, 200);
        errdefer allocator.free(result_buffer);

        var result_string_length: c.SQLSMALLINT = 0;
        run_loop: while (true) {
            const result = c.SQLGetInfo(self.handle, @intFromEnum(info_type), result_buffer.ptr, @as(c.SQLSMALLINT, @intCast(result_buffer.len)), &result_string_length);
            switch (@as(SqlReturn, @enumFromInt(result))) {
                .success, .success_with_info => {
                    const value = info_type.getValue(result_buffer, @as(usize, @intCast(result_string_length)));
                    if (!value.isStringType()) {
                        allocator.free(result_buffer);
                    }
                    return value;
                },
                .invalid_handle => @panic("Connection.getInfo passed invalid handle"),
                else => switch (self.getLastError()) {
                    error.StringRightTrunc => {
                        result_buffer = try allocator.realloc(result_buffer, @as(usize, @intCast(result_string_length)));
                        continue :run_loop;
                    },
                    else => |err| return err,
                },
            }
        }
    }

    pub fn getAttribute(self: Connection, comptime attribute: Attribute, allocator: Allocator) !?AttributeValue {
        var value = try allocator.alloc(u8, 100);
        defer allocator.free(value);

        var attribute_str_len: i32 = 0;
        attr_loop: while (true) {
            const result = c.SQLGetConnectAttr(self.handle, @intFromEnum(attribute), value.ptr, @as(c_long, @intCast(value.len)), &attribute_str_len);
            switch (@as(SqlReturn, @enumFromInt(result))) {
                .success, .success_with_info => return attribute.getAttributeValue(value),
                .no_data => return null,
                .invalid_handle => @panic("Connection.getAttribute passed invalid handle"),
                else => switch (self.getLastError()) {
                    error.StringRightTrunc => {
                        value = try allocator.realloc(value, @as(usize, @intCast(attribute_str_len)) + 1);
                        continue :attr_loop;
                    },
                    else => |err| return err,
                },
            }
        }
    }

    pub fn setAttribute(self: Connection, value: AttributeValue) !void {
        const result = switch (value) {
            // For string attributes, pass the pointers to the strings directly
            .CurrentCatalog => |v| c.SQLSetConnectAttr(self.handle, @intFromEnum(value), v.ptr, @as(c_int, @intCast(v.len))),
            .Tracefile, .TranslateLib => |v| c.SQLSetConnectAttr(self.handle, @intFromEnum(value), v.ptr, @as(c_int, @intCast(v.len))),
            else => blk: {
                // For integer attributes, get the value and then cast it to ?*anyopaque to pass it on
                var result_buffer: [@sizeOf(u32)]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(result_buffer[0..]);
                _ = try value.getValue(fba.allocator());

                const int_val = std.mem.bytesToValue(u32, &result_buffer);
                break :blk c.SQLSetConnectAttr(self.handle, @intFromEnum(std.meta.activeTag(value)), @as(?*anyopaque, @ptrFromInt(int_val)), 0);
            },
        };
        return switch (@as(SqlReturn, @enumFromInt(result))) {
            .success, .success_with_info => {},
            .invalid_handle => @panic("Connection.setAttribute passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn getLastError(self: Connection) odbc_error.LastError {
        return odbc_error.getLastError(odbc.HandleType.connection, self.handle);
    }

    pub fn getErrors(self: Connection, allocator: Allocator) ![]odbc_error.SqlState {
        return try odbc_error.getErrors(allocator, odbc.HandleType.connection, self.handle);
    }

    pub fn getDiagnosticRecords(self: Connection, allocator: Allocator) ![]odbc_error.DiagnosticRecord {
        return try odbc_error.getDiagnosticRecords(allocator, odbc.HandleType.connection, self.handle);
    }
};
