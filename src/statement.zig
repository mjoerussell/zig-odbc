const std = @import("std");
const Allocator = std.mem.Allocator;

const Connection = @import("connection.zig").Connection;

const c = @import("c.zig");

const unionInitEnum = @import("util.zig").unionInitEnum;

const odbc = @import("types.zig");
const SqlReturn = odbc.SqlReturn;

const odbc_error = @import("error.zig");
const SqlState = odbc_error.SqlState;
const ReturnError = odbc_error.ReturnError;
const LastError = odbc_error.LastError;

pub const StatementInitError = LastError||error{InvalidHandle};

pub const Statement = struct {
    pub const Attribute = odbc.StatementAttribute;
    pub const AttributeValue = odbc.StatementAttributeValue;

    handle: *c_void,

    /// Allocate a new statement handle, using the provided connection as the parent.
    pub fn init(connection: Connection) StatementInitError!Statement {
        var result: Statement = undefined;
        const alloc_result = c.SQLAllocHandle(@enumToInt(odbc.HandleType.Statement), connection.handle, @ptrCast([*c]?*c_void, &result.handle));
        return switch (@intToEnum(SqlReturn, alloc_result)) {
            .Success, .SuccessWithInfo => result,
            .InvalidHandle => StatementInitError.InvalidHandle,
            else => connection.getLastError(),
        };
    }

    /// Free this statement handle. If this is successful then the statement object becomes invalidated and
    /// should no longer be used.
    pub fn deinit(self: *Statement) LastError!void {
        const result = c.SQLFreeHandle(@enumToInt(odbc.HandleType.Statement), self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success => {},
            .InvalidHandle => @panic("Statement.deinit passed invalid handle"), 
            else => self.getLastError(),
        };
    }

    /// Bind a buffer to a column in the statement result set. Once columns have been bound and a result set created by calling `execute`, `executeDirect`, or any
    /// other function that creates a result set, `fetch` or `fetchDirect` can be used to put data into the bound buffers.
    /// * column_number - The column to bind. Column numbers start at 1
    /// * target_type - The C data type of the buffer.
    /// * target_buffer - The buffer that data will be put into. 
    /// * str_len_or_ind_ptr - An indicator value that will later be used to determine the length of data put into `target_buffer`.
    pub fn bindColumn(
        self: *Statement, 
        column_number: u16, 
        target_type: odbc.CType, 
        target_buffer: anytype, 
        str_len_or_ind_ptr: [*]c_longlong, 
        column_size: ?usize
    ) LastError!void {
        const BufferInfo = @typeInfo(@TypeOf(target_buffer));
        comptime {
            switch (BufferInfo) {
                .Pointer => switch (BufferInfo.Pointer.size) {
                    .Slice => {},
                    else => @compileError("Expected a slice for parameter target_buffer, got " ++ @typeName(@TypeOf(target_buffer)))
                },
                else => @compileError("Expected a slice for parameter target_buffer, got " ++ @typeName(@TypeOf(target_buffer)))
            }
        }

        const result = c.SQLBindCol(
            self.handle, 
            column_number, 
            @enumToInt(target_type), 
            @ptrCast(?*c_void, target_buffer.ptr), 
            @intCast(c_longlong, column_size orelse target_buffer.len * @sizeOf(BufferInfo.Pointer.child)), 
            str_len_or_ind_ptr
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.bindColumn passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Bind a value to a parameter marker in a SQL statement.
    /// * parameter_number: The parameter to bind. Parameter numbers start at 1
    /// * io_type: The parameter type. Roughly speaking, parameters can be **input** params, where the application puts data into the parameter, or **output** params,
    ///            where the driver will put data into the buffer after evaluated the statement.
    /// * value_type: The C type of the parameter data.
    /// * parameter_type: The SQL type of the parameter in the statement
    /// * value: A pointer to a value to bind. If `io_type` is an output type, this pointer will contain the result of getting param data after execution.
    /// * decimal_digits: The number of digits to use for floating point numbers. `null` for other data types.
    /// * str_len_or_ind_ptr: A pointer to a value describing the parameter's length.
    // pub fn bindParameter(self: *Statement, parameter_number: u16, io_type: odbc.InputOutputType, comptime value_type: odbc.CType, parameter_type: odbc.SqlType, value: *value_type.toType(), decimal_digits: ?u16, str_len_or_ind_ptr: *c.SQLLEN) ReturnError!void {
    pub fn bindParameter(
        self: *Statement, 
        parameter_number: u16, 
        io_type: odbc.InputOutputType, 
        value_type: odbc.CType, 
        parameter_type: odbc.SqlType, 
        value: *c_void, 
        decimal_digits: ?u16, 
        str_len_or_ind_ptr: *c.SQLLEN
    ) LastError!void {
        const result = c.SQLBindParameter(
            self.handle, 
            parameter_number, 
            @enumToInt(io_type), 
            @enumToInt(value_type), 
            @enumToInt(parameter_type), 
            @sizeOf(@TypeOf(value)),
            @intCast(c.SQLSMALLINT, decimal_digits orelse 0),
            value, 
            @sizeOf(@TypeOf(value)),
            str_len_or_ind_ptr
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.bindParameter passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn bulkOperations(self: *Statement, operation: odbc.BulkOperation) LastError!void {
        const result = c.SQLBulkOperations(self.handle, @enumToInt(operation));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.bulkOperations passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn cancel(self: *Statement) LastError!void {
        const result = c.SQLCancel(self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.cancel passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn closeCursor(self: *Statement) LastError!void {
        const result = c.SQLCloseCursor(self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.closeCursor passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn columnPrivileges(self: *Statement, catalog_name: []const u8, schema_name: []const u8, table_name: []const u8, column_name: []const u8) !void {
        const result = c.SQLColumnPrivileges(self.handle, catalog_name.ptr, @intCast(u16, catalog_name.len), schema_name.ptr, @intCast(u16, schema_name.len), table_name.ptr, @intCast(u16, table_name.len), column_name.ptr, @intCast(u16, column_name.len));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.columnPrivileges returned invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn columns(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, table_name: []const u8, column_name: ?[]const u8) !void {
        const result = c.SQLColumns(
            self.handle, 
            if (catalog_name) |cn| @intToPtr([*c]u8, @ptrToInt(cn.ptr)) else null, 
            if (catalog_name) |cn| @intCast(c_short, cn.len) else 0, 
            if (schema_name) |sn| @intToPtr([*c]u8, @ptrToInt(sn.ptr)) else null, 
            if (schema_name) |sn| @intCast(c_short, sn.len) else 0, 
            @intToPtr([*c]u8, @ptrToInt(table_name.ptr)), 
            @intCast(c_short, table_name.len),
            if (column_name) |cn| @intToPtr([*c]u8, @ptrToInt(cn.ptr)) else null,
            if (column_name) |cn| @intCast(c_short, cn.len) else 0
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.columns passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn getColumnAttribute(self: *Statement, allocator: Allocator, column_number: usize, comptime attr: odbc.ColumnAttribute) !odbc.ColumnAttributeValue {
        var string_attr_length: c_short = 0;
        // First call to get the length of the string required to hold the string attribute value, if applicable
        _ = c.SQLColAttribute(self.handle, @intCast(c_ushort, column_number), @enumToInt(attr), null, 0, &string_attr_length, null);

        var string_attr: [:0]u8 = try allocator.allocSentinel(u8, @intCast(usize, string_attr_length), 0);
        errdefer allocator.free(string_attr);

        var numeric_attribute: c_longlong = 0;
        const result = c.SQLColAttribute(
            self.handle, 
            @intCast(c_ushort, column_number), 
            @enumToInt(attr), 
            string_attr.ptr, 
            string_attr_length + 1, 
            &string_attr_length, 
            &numeric_attribute
        );

        if (string_attr_length == 0) {
            allocator.free(string_attr);
        }

        switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {
                return unionInitEnum(odbc.ColumnAttributeValue, attr, switch (attr) {
                    .AutoUniqueValue => numeric_attribute == c.SQL_TRUE,
                    .BaseColumnName => string_attr[0..@intCast(usize, string_attr_length)],
                    .BaseTableName => string_attr,
                    .CaseSensitive => numeric_attribute == c.SQL_TRUE,
                    .CatalogName => string_attr,
                    .ConciseType => @intToEnum(odbc.SqlType, numeric_attribute),
                    .Count => numeric_attribute,
                    .DisplaySize => numeric_attribute,
                    .FixedPrecisionScale => numeric_attribute,
                    .Label => string_attr,
                    .Length => numeric_attribute,
                    .LiteralPrefix => string_attr,
                    .LiteralSuffix => string_attr,
                    .LocalTypeName => string_attr,
                    .Name => string_attr,
                    .Nullable => @intToEnum(odbc.ColumnAttributeValue.Nullable, numeric_attribute),
                    .NumericPrecisionRadix => numeric_attribute,
                    .OctetLength => numeric_attribute,
                    .Precision => numeric_attribute,
                    .Scale => numeric_attribute,
                    .SchemaName => string_attr,
                    .Searchable => @intToEnum(odbc.ColumnAttributeValue.Searchable, numeric_attribute),
                    .TableName => string_attr,
                    .Type => @intToEnum(odbc.SqlType, @intCast(c_short, numeric_attribute)),
                    .TypeName => string_attr,
                    .Unnamed => numeric_attribute == c.SQL_NAMED,
                    .Unsigned => numeric_attribute == c.SQL_TRUE,
                    .Updatable => @intToEnum(odbc.ColumnAttributeValue.Updatable, numeric_attribute),
                });
            },
            .InvalidHandle => @panic("Statement.getColumnAttribute passed invalid handle"),
            .StillExecuting => return ReturnError.StillExecuting,
            else => return ReturnError.Error,
        }
    }

    pub fn describeColumn(self: *Statement, allocator: *Allocator, column_number: c_ushort) !odbc.ColumnDescriptor {
        var column_desc: odbc.ColumnDescriptor = undefined;
        
        var name_length: c_short = 0;
        _ = c.SQLDescribeCol(self.handle, column_number, null, 0, &name_length, null, null, null, null);

        column_desc.name = try allocator.allocSentinel(u8, name_length, 0);

        const result = c.SQLDescribeCol(
            self.handle, 
            column_number, 
            column_desc.name.ptr, 
            name_length + 1, 
            &name_length, 
            @ptrCast(*odbc.SQLSMALLINT, &column_desc.data_type), 
            &column_desc.size, 
            &column_desc.decimal_digits, 
            @ptrCast(*odbc.SQLSMALLINT, &column_desc.nullable)
        );

        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => column_desc,
            .InvalidHandle => @panic("Statement.describeColumn passed invalid handle"),
            .StillExecuting => ReturnError.StillExecuting,
            else => ReturnError.Error,
        };
    }

    pub fn describeParameter(self: *Statement, parameter_number: c_ushort) ReturnError!odbc.ParameterDescriptor {
        var param_desc: odbc.ParameterDescriptor = undefined;
        
        const result = c.SQLDescribeParam(
            self.handle, 
            parameter_number, 
            @ptrCast(*odbc.SQLSMALLINT, &param_desc.data_type), 
            &param_desc.size, 
            &param_desc.decimal_digits, 
            @ptrCast(*odbc.SQLSMALLINT, &param_desc.nullable)
        );

        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => param_desc,
            .InvalidHandle => @panic("Statement.describeColumn passed invalid handle"),
            .StillExecuting => ReturnError.StillExecuting,
            else => ReturnError.Error,
        };
    }

    /// Prepare a SQL statement for execution.
    pub fn prepare(self: *Statement, sql_statement: []const u8) !void {
        const result = c.SQLPrepare(self.handle, @intToPtr([*]u8, @ptrToInt(sql_statement.ptr)), @intCast(c.SQLINTEGER, sql_statement.len));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.prepare passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Execute a prepared SQL statement.
    pub fn execute(self: *Statement) odbc_error.LastError!void {
        const result = c.SQLExecute(self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.execute passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Execute a SQL statement directly. This is the fastest way to execute a SQL statement once.
    pub fn executeDirect(self: *Statement, statement_text: []const u8) !void {
        const result = c.SQLExecDirect(self.handle, @intToPtr([*c]u8, @ptrToInt(statement_text.ptr)), @intCast(c.SQLINTEGER, statement_text.len));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.executeDirect passed invalid handle"),
            else => self.getLastError(),
        };
    }

    /// Fetch the next rowset of data from the result set and return data in all bound columns.
    pub fn fetch(self: *Statement) !bool {
        const result = c.SQLFetch(self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => true,
            .InvalidHandle => @panic("Statement.fetch passed invalid handle"),
            .StillExecuting => ReturnError.StillExecuting,
            .NoData => false,
            else => self.getLastError(),
        };
    }

    /// Fetch a specified rowset of data from the result set and return data in all bound columns. Rowsets
    /// can be specified at an absolute position, relative position, or by bookmark.
    pub fn fetchScroll(self: *Statement, orientation: odbc.FetchOrientation, offset: usize) !bool {
        const result = c.SQLFetchScroll(self.handle, @enumToInt(orientation), @intCast(c_longlong, offset));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => true,
            .InvalidHandle => @panic("Statement.fetchScroll passed invalid handle"),
            .StillExecuting => ReturnError.StillExecuting,
            .NoData => false,
            else => self.getLastError(),
        };
    }

    pub fn primaryKeys(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, table_name: []const u8) !void {
        const result = c.SQLPrimaryKeys(
            self.handle,
            if (catalog_name) |cn| cn.ptr else null,
            if (catalog_name) |cn| cn.len else 0,
            if (schema_name) |sn| sn.ptr else null,
            if (schema_name) |sn| sn.len else 0,
            table_name.ptr,
            table_name.len
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.primaryKeys passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn foreignKeys(
        self: *Statement, 
        pk_catalog_name: ?[]const u8, 
        pk_schema_name: ?[]const u8, 
        pk_table_name: ?[]const u8, 
        fk_catalog_name: ?[]const u8, 
        fk_schema_name: ?[]const u8, 
        fk_table_name: ?[]const u8
    ) !void {
        const result = c.SQLForeignKeys(
            self.handle,
            if (pk_catalog_name) |cn| cn.ptr else null,
            if (pk_catalog_name) |cn| cn.len else 0,    
            if (pk_schema_name) |sn| sn.ptr else null,
            if (pk_schema_name) |sn| sn.len else 0,    
            if (pk_table_name) |tn| tn.ptr else null,
            if (pk_table_name) |tn| tn.len else 0,    
            if (fk_catalog_name) |cn| cn.ptr else null,
            if (fk_catalog_name) |cn| cn.len else 0,    
            if (fk_schema_name) |sn| sn.ptr else null,
            if (fk_schema_name) |sn| sn.len else 0,    
            if (fk_table_name) |tn| tn.ptr else null,
            if (fk_table_name) |tn| tn.len else 0,    
        );

        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.foreignKeys passed invalid handle"),
            .StillExecuting => ReturnError.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn getCursorName(self: *Statement, allocator: *Allocator) ![]const u8 {
        var name_length: c_short = 0;
        _ = c.SQLGetCursorName(self.handle, null, 0, &name_length);

        var name_buffer = try allocator.allocSentinel(u8, name_length, 0);
        errdefer allocator.free(name_buffer);

        const result = c.SQLGetCursorName(self.handle, name_buffer.ptr, @intCast(c_short, name_buffer.len), &name_length);

        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => name_buffer,
            .InvalidHandle => @panic("Statement.getCursorName passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn getData(self: *Statement, allocator: *Allocator, column_number: usize, comptime target_type: odbc.CType) !?target_type.toType() {
        var result_data = try std.ArrayList(u8).initCapacity(allocator, 500);
        errdefer result_data.deinit();

        var target_buffer: [500]u8 = undefined;
        var bytes_retrieved: c_longlong = 0;

        fetch_loop: while (true) {
            const result = c.SQLGetData(
                self.handle, 
                @intCast(c_ushort, column_number), 
                @enumToInt(target_type), 
                @ptrCast([*c]c_void, target_buffer.ptr), 
                @intCast(c_longlong, target_buffer.len), 
                &bytes_retrieved
            );
            const result_type = @intToEnum(SqlReturn, result);
            switch (result_type) {
                .Success, .SuccessWithInfo, .NoData => {
                    switch (bytes_retrieved) {
                        c.SQL_NULL_DATA, c.SQL_NO_TOTAL => return null,
                        else => {
                            try result_data.appendSlice(target_buffer[0..bytes_retrieved]);
                            if (result_type == .SuccessWithInfo) {
                                // SuccessWithInfo might indicate that only part of the column was retrieved, and in that case we need to 
                                // continue fetching the rest of it. If we're getting long data, SQLGetData will return NoData
                                var error_buffer: [@sizeOf(odbc_error.SqlState) * 3]u8 = undefined;
                                var fba = std.heap.FixedBufferAllocator.init(error_buffer);
                                const errors = try self.getErrors(&fba.allocator);
                                for (errors) |err| if (err == .StringRightTrunc) {
                                    // SQLGetData will terminate long data with a null byte, so we have to remove it before the next fetch
                                    _ = result_data.pop();
                                    continue :fetch_loop;
                                };
                                // If the error wasn't StringRightTrunc then it's not something that needs to be handled differently than
                                // Success
                            }
                            const data = result_data.toOwnedSlice();
                            defer if (!target_type.isSlice()) allocator.free(data);

                            return std.mem.bytesToValue(target_type.toType(), data);
                        }
                    }
                },
                .InvalidHandle => @panic("Statement.getData passed invalid handle"),
                .StillExecuting => return ReturnError.StillExecuting,
                else => return self.getLastError(),
            }
        }
    }

    pub fn getAttribute(self: *Statement, attr: Attribute) !AttributeValue {
        var result_buffer: [100]u8 = undefined;
        var string_length_result: u32 = 0;
        const result = c.SQLGetStmtAttr(self.handle, @enumToInt(attr), @ptrCast(*c_void, &result_buffer), @intCast(u32, result_buffer.len), @ptrCast([*c]c_long, &string_length_result));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => attr.getValue(result_buffer[0..]),
            .InvalidHandle => @panic("Statement.getAttribute passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn setAttribute(self: *Statement, attr_value: AttributeValue) !void {
        const result = switch (attr_value) {
            .ParamOperationPointer => |v| c.SQLSetStmtAttr(self.handle, @enumToInt(Attribute.ParamOperationPointer), @ptrCast([*]std.meta.Tag(AttributeValue.ParamOperation), v), 0),
            .ParamStatusPointer => |v| c.SQLSetStmtAttr(self.handle, @enumToInt(Attribute.ParamStatusPointer), @ptrCast([*]std.meta.Tag(AttributeValue.ParamStatus), v), 0),
            .RowOperationPointer => |v| c.SQLSetStmtAttr(self.handle, @enumToInt(Attribute.RowOperationPointer), @ptrCast([*]std.meta.Tag(AttributeValue.RowOperation), v), 0),
            .RowStatusPointer => |v| c.SQLSetStmtAttr(self.handle, @enumToInt(Attribute.RowStatusPointer), @ptrCast([*]std.meta.Tag(AttributeValue.RowStatus), v), 0),
            else => blk: {
                var buffer: [100]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
                
                _ = try attr_value.valueAsBytes(fba.allocator());
                const int_value = std.mem.bytesAsValue(u64, buffer[0..@sizeOf(u64)]);

                break :blk c.SQLSetStmtAttr(self.handle, @enumToInt(std.meta.activeTag(attr_value)), @intToPtr(?*c_void, @intCast(usize, int_value.*)), 0);
            }
        };

        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.setAttribute passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn getTypeInfo(self: *Statement, data_type: odbc.SqlType) !void {
        const result = c.SQLGetTypeInfo(self.handle, @enumToInt(data_type));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.getTypeInfo passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn moreResults(self: *Statement) !void {
        const result = c.SQLMoreResults(self.handle);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.moreResults passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn numParams(self: *Statement) !usize {
        var num_params: c.SQLSMALLINT = 0;
        const result = c.SQLNumParams(self.handle, &num_params);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => @intCast(usize, num_params),
            .InvalidHandle => @panic("Statement.numParams passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    /// Get the number of columns in the current result set. If no result set was created, returns 0.
    pub fn numResultColumns(self: *Statement) !usize {
        var num_result_columns: c.SQLSMALLINT = 0;
        const result = c.SQLNumResultCols(self.handle, &num_result_columns);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => @intCast(usize, num_result_columns),
            .InvalidHandle => @panic("Statement.numResultColumns passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn paramData(self: *Statement, value_ptr: *c_void) !void {
        const result = c.SQLParamData(self.handle, &value_ptr);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.paramData passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn procedureColumns(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, procedure_name: []const u8, column_name: []const u8) !void {
        const result = c.SQLProcedureColumns(
            self.handle,
            if (catalog_name) |cn| cn.ptr else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| sn.ptr else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            procedure_name.ptr,
            @intCast(c.SQLSMALLINT, procedure_name.len),
            column_name.ptr,
            @intCast(c.SQLSMALLINT, column_name.len)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.procedureColumns passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    /// Return the list of procedure names in a data source.
    pub fn procedures(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, procedure_name: []const u8) !void {
        const result = c.SQLProcedures(
            self.handle,
            if (catalog_name) |cn| cn.ptr else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| sn.ptr else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            procedure_name.ptr,
            @intCast(c.SQLSMALLINT, procedure_name.len)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.procedures passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn putData(self: *Statement, data: anytype, str_len_or_ind_ptr: c_longlong) !void {
        const result = c.SQLPutData(self.handle, @ptrCast([*c]c_void, &data), str_len_or_ind_ptr);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.putData passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    /// Get the number of rows affected by an UPDATE, INSERT, or DELETE statement.
    pub fn rowCount(self: *Statement) !usize {
        var row_count: c.SQLLEN = 0;
        const result = c.SQLRowCount(self.handle, &row_count);
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => @intCast(usize, row_count),
            .InvalidHandle => @panic("Statement.rowCount passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn setCursorName(self: *Statement, cursor_name: []const u8) !void {
        const result = c.SQLSetCursorName(self.handle, cursor_name.ptr, @intCast(c.SQLSMALLINT, cursor_name.len));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.setCursorName passed invalid handle"),
            else => self.getLastError(),
        };
    }

    pub fn setPos(self: *Statement, row_number: usize, operation: odbc.CursorOperation, lock_type: odbc.LockType) !void {
        const result = c.SQLSetPos(self.handle, @intCast(c.SQLSETPOSIROW, row_number), @enumToInt(operation), @enumToInt(lock_type));
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.setPos passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn specialColumns(
        self: *Statement, 
        identifier_type: odbc.ColumnIdentifierType, 
        catalog_name: ?[]const u8, 
        schema_name: ?[]const u8, 
        table_name: []const u8, 
        row_id_scope: odbc.RowIdScope, 
        nullable: odbc.Nullable
    ) !void {
        const result = c.SQLSpecialColumns(
            self.handle,
            @enumToInt(identifier_type),
            if (catalog_name) |cn| cn.ptr else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| sn.ptr else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            table_name.ptr,
            @intCast(c.SQLSMALLINT, table_name.len),
            @enumToInt(row_id_scope),
            @enumToInt(nullable)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.specialColumns passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn statistics(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, table_name: []const u8, unique: bool, reserved: odbc.Reserved) !void {
        const result = c.SQLStatistics(
            self.handle, 
            if (catalog_name) |cn| cn.ptr else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| sn.ptr else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            table_name.ptr,
            @intCast(c.SQLSMALLINT, table_name.len),
            if (unique) c.SQL_INDEX_UNIQUE else c.SQL_INDEX_ALL,
            @enumToInt(reserved)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.statistics passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn tablePrivileges(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, table_name: []const u8) !void {
        const result = c.SQLTablePrivileges(
            self.handle,
            if (catalog_name) |cn| @intToPtr([*c]u8, @ptrToInt(cn.ptr)) else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| @intToPtr([*c]u8, @ptrToInt(sn.ptr)) else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            @intToPtr([*c]u8, @ptrToInt(table_name.ptr)),
            @intCast(c.SQLSMALLINT, table_name.len)
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.tablePrivileges passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn tables(self: *Statement, catalog_name: ?[]const u8, schema_name: ?[]const u8, table_name: ?[]const u8, table_type: ?[]const u8) !void {
        const result = c.SQLTables(
            self.handle,
            if (catalog_name) |cn| @intToPtr([*c]u8, @ptrToInt(cn.ptr)) else null,
            if (catalog_name) |cn| @intCast(c.SQLSMALLINT, cn.len) else 0,
            if (schema_name) |sn| @intToPtr([*c]u8, @ptrToInt(sn.ptr)) else null,
            if (schema_name) |sn| @intCast(c.SQLSMALLINT, sn.len) else 0,
            if (table_name) |tn| @intToPtr([*c]u8, @ptrToInt(tn.ptr)) else null,
            if (table_name) |tn| @intCast(c.SQLSMALLINT, tn.len) else 0,
            if (table_type) |tt| @intToPtr([*c]u8, @ptrToInt(tt.ptr)) else null,
            if (table_type) |tt| @intCast(c.SQLSMALLINT, tt.len) else 0,
        );
        return switch (@intToEnum(SqlReturn, result)) {
            .Success, .SuccessWithInfo => {},
            .InvalidHandle => @panic("Statement.tables passed invalid handle"),
            .StillExecuting => error.StillExecuting,
            else => self.getLastError(),
        };
    }

    pub fn getAllCatalogs(self: *Statement) !void {
        return try self.tables(c.SQL_ALL_CATALOGS, "", "", "");
    }

    pub fn getAllSchemas(self: *Statement) !void {
        return try self.tables("", c.SQL_ALL_SCHEMAS, "", "");
    }

    pub fn getAllTableTypes(self: *Statement) !void {
        return try self.tables("", "", "", c.SQL_ALL_TABLE_TYPES);
    }

    pub fn getLastError(self: *const Statement) odbc_error.LastError {
        return odbc_error.getLastError(odbc.HandleType.Statement, self.handle);
    }

    pub fn getErrors(self: *Statement, allocator: Allocator) ![]odbc_error.SqlState {
        return try odbc_error.getErrors(allocator, odbc.HandleType.Statement, self.handle);
    }

    pub fn getDiagnosticRecords(self: *Statement, allocator: Allocator) ![]odbc_error.DiagnosticRecord {
        return try odbc_error.getDiagnosticRecords(allocator, odbc.HandleType.Statement, self.handle);
    }

};