const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @import("c.zig");
const odbc = @import("types.zig");
const HandleType = odbc.HandleType;
const SqlReturn = odbc.SqlReturn;

const odbc_error = @import("error.zig");
const ReturnError = odbc_error.ReturnError;
const OdbcError = odbc_error.OdbcError;

pub const Environment = struct {
    pub const Attribute = odbc.EnvironmentAttribute;
    pub const AttributeValue = odbc.EnvironmentAttributeValue;

    handle: *c_void,

    pub fn init() ReturnError!Environment {
        var result: Environment = undefined;
        const alloc_result = c.SQLAllocHandle(@enumToInt(HandleType.Environment), null, @ptrCast([*c]?*c_void, &result.handle));
        return switch (@intToEnum(SqlReturn, alloc_result)) {
            .InvalidHandle => @panic("Environment init passed invalid handle type"), 
            .Error => error.Error,
            else => result,
        };
    }

    /// Free the environment handle. If this succeeds, then it's invalid to try to use this environment
    /// again. If this fails, then the environment handle will still be active and must be deinitialized
    /// again after fixing the errors.
    pub fn deinit(self: *Environment) !void {
        const result = c.SQLFreeHandle(@enumToInt(HandleType.Environment), self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Environment deinit passed invalid handle type"), // Handle type is hardcoded above, this should never be reached
            .Error => self.getLastError(),
            else => {},
        };
    }

    pub fn getDataSource(self: *Environment, allocator: *Allocator, direction: odbc.Direction) !?odbc.DataSource {
        var server_name_buf = try allocator.alloc(u8, 100);
        var description_buf = try allocator.alloc(u8, 100);
        var server_name_len: i16 = 0;
        var description_len: i16 = 0;

        run_loop: while (true) {
            const result = c.SQLDataSources(self.handle, @enumToInt(direction), server_name_buf.ptr, @intCast(i16, server_name_buf.len), &server_name_len, description_buf.ptr, @intCast(i16, description_buf.len), &description_len);
            switch (@intToEnum(SqlReturn, result)) {
                .Success => return odbc.DataSource{
                    .server_name = server_name_buf[0..@intCast(usize, server_name_len)],
                    .description = description_buf[0..@intCast(usize, description_len)],
                },
                .SuccessWithInfo => switch (self.getLastError()) {
                    error.StringRightTrunc => {
                        server_name_buf = try allocator.resize(server_name_buf, @intCast(usize, server_name_len + 1));
                        description_buf = try allocator.resize(description_buf, @intCast(usize, description_len + 1));
                        continue :run_loop;
                    },
                    else => |err| return err,
                },
                .NoData => return null,
                else => return self.getLastError(),
            }
        }
    }

    pub fn getDriver(self: *Environment, allocator: *Allocator, direction: odbc.Direction) !?odbc.Driver {
        var description_buf = try allocator.alloc(u8, 100);
        var attribute_buf = try allocator.alloc(u8, 100);
        var description_len: i16 = 0;
        var attributes_len: i16 = 0;
        
        run_loop: while (true) {
            const result = c.SQLDrivers(self.handle, @enumToInt(direction), description_buf.ptr, @intCast(i16, description_buf.len), &description_len, attribute_buf.ptr, @intCast(i16, attribute_buf.len), &attributes_len);
            switch (@intToEnum(SqlReturn, result)) {
                .Success => return odbc.Driver{
                    .description = description_buf[0..@intCast(usize, description_len)],
                    .attributes = attribute_buf[0..@intCast(usize, attributes_len)]
                },
                .NoData => return null,
                .SuccessWithInfo => switch (self.getLastError()) {
                    error.StringRightTrunc => {
                        description_buf = try allocator.resize(description_buf, @intCast(usize, description_len + 1));
                        attribute_buf = try allocator.resize(attribute_buf, @intCast(usize, attributes_len + 1));
                        continue :run_loop;
                    },
                    else => |err| return err,
                },
                else => return self.getLastError(),
            }
        }
    }

    pub fn getAllDrivers(self: *Environment, allocator: *Allocator) ![]odbc.Driver {
        var driver_list = std.ArrayList(odbc.Driver).init(allocator);
        var direction: odbc.Direction = .FetchFirst;
        while (true) {
            const driver = self.getDriver(allocator, direction) catch break;
            if (driver) |d| {
                try driver_list.append(d);
                direction = .FetchNext;
            } else break;
        }

        return driver_list.toOwnedSlice();
    }

    pub fn getAttribute(self: *Environment, attribute: Attribute) !AttributeValue {
        var value: i32 = 0;
        const result = c.SQLGetEnvAttr(self.handle, @enumToInt(attribute), &value, 0, null);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => attribute.getAttributeValue(value),
            else => self.getLastError(),
        };
    }

    pub fn setAttribute(self: *Environment, value: AttributeValue) !void {
        const result = c.SQLSetEnvAttr(self.handle, @enumToInt(std.meta.activeTag(value)), @intToPtr(*c_void, value.getValue()), 0);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            else => self.getLastError(),
        };
    }

    /// Set the OdbcVersion attribute for this environment. You must set the version immediately after
    /// allocating an environment, either using this function or `setAttribute(.{ .OdbcVersion = <version> })`.
    pub fn setOdbcVersion(self: *Environment, version: AttributeValue.OdbcVersion) !void {
        try self.setAttribute(.{ .OdbcVersion = version });
    }

    pub fn getOdbcVersion(self: *Environment) !AttributeValue.OdbcVersion {
        const attr = try self.getAttribute(.OdbcVersion);
        return attr.OdbcVersion;
    }

    pub fn getLastError(self: *const Environment) odbc_error.LastError {
        return odbc_error.getLastError(odbc.HandleType.Environment, self.handle);
    }

    pub fn getErrors(self: *Environment, allocator: *Allocator) ![]odbc_error.SqlState {
        return try odbc_error.getErrors(allocator, HandleType.Environment, self.handle);
    }

    pub fn getDiagnosticRecords(self: *Environment, allocator: *Allocator) ![]odbc_error.DiagnosticRecord {
        return try odbc_error.getDiagnosticRecords(allocator, HandleType.Environment, self.handle);
    }

};