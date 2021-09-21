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

    handle: *c_void,

    connected: bool = false,

    pub fn init(environment: *Environment) ReturnError!Connection {
        var result: Connection = undefined;
        const alloc_result = c.SQLAllocHandle(@enumToInt(HandleType.Connection), environment.handle, @ptrCast([*c]?*c_void, &result.handle));
        return switch (@intToEnum(SqlReturn, alloc_result)) {
            .InvalidHandle => error.InvalidHandle,
            .Error => error.Error,
            else => result,
        };
    }

    pub fn deinit(self: *Connection) !void {
        if (self.connected) try self.disconnect();
        const result = c.SQLFreeHandle(@enumToInt(HandleType.Connection), self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            else => error.Error
        };
    }

    pub fn connect(self: *Connection, server_name: []const u8, user_name: []const u8, password: []const u8) ReturnError!void {
        const result = c.SQLConnect(
            self.handle, 
            @intToPtr([*c]u8, @ptrToInt(server_name.ptr)), 
            @intCast(i16, server_name.len), 
            @intToPtr([*c]u8, @ptrToInt(user_name.ptr)), 
            @intCast(i16, user_name.len), 
            @intToPtr([*c]u8, @ptrToInt(password.ptr)), 
            @intCast(i16, password.len)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {
                self.connected = true;
            },
            // @todo Async handling
            else => error.Error
        };
    }

    pub fn connectExtended(self: *Connection, connection_string: []const u8, completion: odbc.DriverCompletion) ReturnError!void {
        const result = c.SQLDriverConnect(
            self.handle, 
            null, 
            @intToPtr([*c]u8, @ptrToInt(connection_string.ptr)), 
            @intCast(c_short, connection_string.len), 
            null, 
            0, 
            null, 
            @enumToInt(completion)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {
                self.connected = true;
            },
            // @todo Async handling
            // @todo Better error handling
            else => error.Error
        };
    }

    pub fn browseConnect(self: *Connection, allocator: *Allocator, partial_connection_string: []const u8) !?[]const u8 {
        // @todo Maybe make a structure for connection string info, so users don't have to build/parse them manually
        //       Probably should at least provide utilities for getting/putting information into them
        var out_string_len: c.SQLSMALLINT = 0;
        var out_string_buffer = try allocator.alloc(u8, 100);
        errdefer allocator.free(out_string_buffer);

        run_loop: while (true) {
            const result = c.SQLBrowseConnect(self.handle, partial_connection_string.ptr, partial_connection_string.len, out_string_buffer.ptr, out_string_buffer.len, &out_string_len);
            switch (@intToEnum(SqlReturn, result)) {
                .Success, .SuccessWithInfo => {
                    // If SQLBrowseConnect returns success, then the user passed all required info and the connection should be established.
                    // Set connected to true and return null to indicate that there is no more info needed.
                    self.connected = true;
                    allocator.free(out_string_buffer);
                    return null;
                },
                .NeedsData => {
                    if (std.mem.eql(u8, partial_connection_string, out_string_buffer)) {
                        // If SQLBrowseConnect returns NeedsData and the out string is unchanged from the input string, that means that there are
                        // unrecoverable errors. The caller of this function can get the error info to see what happened.
                        return error.Error;
                    }
                    // Otherwise, when NeedsData is returned out_string_buffer contains a connection string-like value that indicates
                    // to the user what info they need to pass next
                    return out_string_buffer;
                },
                .InvalidHandle => @panic("Connection.browseConnect passed invalid handle"),
                else => {
                    var error_buffer: [@sizeOf(odbc_error.SqlState)]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(error_buffer);
                    const errors = try self.getErrors(&fba.allocator);
                    for (errors) |e| {
                        if (e == .StringRightTrunc) {
                            // If the error that occurred was StringRightTrunc, then the out string buffer was not big enough
                            // to store the result.
                            out_string_buffer = try allocator.realloc(out_string_buffer, @intCast(usize, out_string_len) + 1);
                            continue :run_loop;
                        }
                    }
                    return error.Error;
                    
                }
            }
        }
    }

    pub fn disconnect(self: *Connection) ReturnError!void {
        const result = c.SQLDisconnect(self.handle);
        return switch(@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {
                self.connected = false;
            },
            // @todo Async handling
            else => error.Error
        };
    }

    pub fn endTransaction(self: *Connection, completion_type: odbc.CompletionType) ReturnError!void {
        const result = c.SQLEndTran(@enumToInt(HandleType.Connection), self.handle, @enumToInt(completion_type));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Connection.endTransaction passed invalid handle"),
            else => error.Error,
        };
    }

    pub fn cancel(self: *Connection) ReturnError!void {
        const result = c.SQLCancelHandle(@enumToInt(HandleType.Connection), self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Connection.cancel passed invalid handle"),
            else => error.Error
        };
    }

    pub fn isFunctionEnabled(self: *Connection, function_id: odbc.FunctionId) bool {
        var supported: c.SQLUSMALLINT = 0;
        const result = c.SQLGetFunctions(self.handle, @enumToInt(function_id), &supported);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => supported == c.SQL_TRUE,
            else => false
        };
    }

    pub fn getAllEnabledFunctions(self: *Connection, allocator: *Allocator) ![]odbc.FunctionId {
        var result_buffer: [c.SQL_API_ODBC3_ALL_FUNCTIONS_SIZE]c.SQLUSMALLINT = undefined;
        var result_list = std.ArrayList(odbc.FunctionId).init(allocator);
        const result = c.SQLGetFunctions(self.handle, c.SQL_API_ODBC3_ALL_FUNCTIONS, @ptrCast([*c]c_ushort, &result_buffer));
        switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {
                // Iterate over all of the function ids and check if they exist. See the SQL_FUNC_EXITS macro
                inline for (@typeInfo(odbc.FunctionId).Enum.fields) |field| {
                    // SQL_FUNC_EXISTS(pfExists,uwAPI) ((*(((UWORD*) (pfExists)) + ((uwAPI) >> 4)) & (1 << ((uwAPI) & 0x000F))) ? SQL_TRUE : SQL_FALSE)
                    const func_exists = (@ptrToInt(@ptrCast(*c_ushort, &result_buffer)) + (field.value >> 4)) & (1 << (field.value & 0x000F)) != 0;
                    if (func_exists) {
                        try result_list.append(@intToEnum(odbc.FunctionId, field.value));
                    }
                }
                return result_list.toOwnedSlice();
            },
            else => return error.Error
        }
    }

    pub fn nativeSql(self: *Connection, allocator: *Allocator, sql_statement: []const u8) ![]const u8 {
        var out_statement_len: c.SQLINTEGER = 0;
        // Allocate a buffer for the out string, allocate the same number of chars as the in string because it's likely to be
        // close
        var out_statement_buffer = allocator.alloc(u8, sql_statement.len);
        errdefer allocator.free(out_statement_buffer);

        run_loop: while (true) {
            const result = c.SQLNativeSql(self.handle, sql_statement.ptr, sql_statement.len, out_statement_buffer.ptr, out_statement_buffer.len, &out_statement_len);
            switch (@intToEnum(SqlReturn, result)) {
                .Success, .SuccessWithInfo => return out_statement_buffer,
                .InvalidHandle => @panic("Connection.nativeSql passed invalid handle"),
                else => {
                    var error_buffer: [@sizeOf(odbc_error.SqlState) * 3]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(error_buffer);
                    const errors = self.getErrors(&fba.allocator) catch return error.Error;
                    for (errors) |e| {
                        if (e == .StringRightTrunc) {
                            // If the out string was truncated, realloc the correct length and run again
                            out_statement_buffer = try allocator.realloc(out_statement_buffer, @intCast(usize, out_statement_len) + 1);
                            continue :run_loop;
                        }
                    }
                    // If the error StringRightTrunc didn't happen, return a generic error for the caller to deal with
                    return error.Error;
                } 
            }
        }
        
    }

    pub fn getInfo(self: *Connection, comptime info_type: InformationType, allocator: *Allocator) !InformationTypeValue {
        var result_buffer = try allocator.alloc(u8, 200);
        errdefer allocator.free(result_buffer);
        
        var result_string_length: c.SQLSMALLINT = 0;
        run_loop: while (true) {
            const result = c.SQLGetInfo(self.handle, @enumToInt(info_type), result_buffer.ptr, @intCast(c.SQLSMALLINT, result_buffer.len), &result_string_length);
            switch (@intToEnum(SqlReturn, result)) {
                .Success, .SuccessWithInfo => {
                    const value = info_type.getValue(result_buffer, @intCast(usize, result_string_length));
                    if (!value.isStringType()) {
                        allocator.free(result_buffer);
                    }
                    return value;
                },
                .InvalidHandle => @panic("Connection.getInfo passed invalid handle"),
                else => {
                    var error_buffer: [@sizeOf(odbc_error.SqlState) * 5]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(error_buffer[0..]);
                    const errors = try self.getErrors(&fba.allocator);
                    for (errors) |e| {
                        if (e == .StringRightTrunc) {
                            result_buffer = try allocator.realloc(result_buffer, @intCast(usize, result_string_length));
                            continue :run_loop;
                        }
                    }
                    return odbc_error.ReturnError.Error;
                }
            }
        }

    }

    pub fn getAttribute(self: *Connection, comptime attribute: Attribute, allocator: *Allocator) !?AttributeValue {
        var value = try allocator.alloc(u8, 100);
        defer allocator.free(value);

        var attribute_str_len: i32 = 0;
        attr_loop: while (true) {
            const result = c.SQLGetConnectAttr(self.handle, @enumToInt(attribute), value.ptr, @intCast(c_long, value.len), &attribute_str_len);
            switch (@intToEnum(SqlReturn, result)) {
                .Success, .SuccessWithInfo => return attribute.getAttributeValue(value),
                .NoData => return null,
                .InvalidHandle => @panic("Connection.getAttribute passed invalid handle"),
                else => {
                    // Get the errors. If the error was that the attribute value string was truncated, realloc more memory
                    // for the string and try again. If it was anything else, just return ReturnError.Error.
                    var error_buffer: [@sizeOf(odbc_error.SqlState) * 5]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(error_buffer[0..]);
                    const errors = self.getErrors(&fba.allocator) catch return ReturnError.Error;
                    for (errors) |err| {
                        if (err == .StringRightTrunc) {
                            value = try allocator.realloc(value, @intCast(usize, attribute_str_len) + 1);
                            // Continue the outer loop to try again
                            continue :attr_loop;
                        }
                    }
                    return ReturnError.Error;
                }
            }
        }
        
    }

    pub fn setAttribute(self: *Connection, value: AttributeValue) !void {
        const result = switch (value) {
            // For string attributes, pass the pointers to the strings directly
            .CurrentCatalog => |v| c.SQLSetConnectAttr(self.handle, @enumToInt(value), v.ptr, @intCast(c_int, v.len)), 
            .Tracefile, .TranslateLib => |v| c.SQLSetConnectAttr(self.handle, @enumToInt(value), v.ptr, @intCast(c_int, v.len)),
            else => blk: {
                // For integer attributes, get the value and then cast it to ?*c_void to pass it on
                var result_buffer: [@sizeOf(u32)]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(result_buffer[0..]);
                _ = try value.getValue(&fba.allocator);

                const int_val = std.mem.bytesToValue(u32, &result_buffer);
                break :blk c.SQLSetConnectAttr(self.handle, @enumToInt(std.meta.activeTag(value)), @intToPtr(?*c_void, int_val), 0);
            }
        };
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Connection.setAttribute passed invalid handle"),
            else => ReturnError.Error
        };
    }

    pub fn getErrors(self: *Connection, allocator: *Allocator) ![]odbc_error.SqlState {
        return try odbc_error.getErrors(allocator, odbc.HandleType.Connection, self.handle);
    }

    pub fn getDiagnosticRecords(self: *Connection, allocator: *Allocator) ![]odbc_error.DiagnosticRecord {
        return try odbc_error.getDiagnosticRecords(allocator, odbc.HandleType.Connection, self.handle);
    }
};