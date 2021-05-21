const std = @import("std");
const bytesToValue = std.mem.bytesToValue;
const toBytes = std.mem.toBytes;
const TagType = std.meta.TagType;

const odbc = @import("c.zig");

const util = @import("util.zig");
const Bitmask = util.Bitmask;
const unionInitEnum = util.unionInitEnum;
const sliceToValue = util.sliceToValue;

/// Return codes that might be returned from ODBC functions.
pub const SqlReturn = enum(odbc.SQLRETURN) {
    Success = odbc.SQL_SUCCESS,
    SuccessWithInfo = odbc.SQL_SUCCESS_WITH_INFO,
    NeedsData = odbc.SQL_NEED_DATA,
    StillExecuting = odbc.SQL_STILL_EXECUTING,
    Error = odbc.SQL_ERROR,
    InvalidHandle = odbc.SQL_INVALID_HANDLE,
    NoData = odbc.SQL_NO_DATA,
    ParamDataAvailable = odbc.SQL_PARAM_DATA_AVAILABLE
};

pub const HandleType = enum(odbc.SQLSMALLINT) {
    Environment = odbc.SQL_HANDLE_ENV,
    Connection = odbc.SQL_HANDLE_DBC,
    Statement = odbc.SQL_HANDLE_STMT,
    Descriptor = odbc.SQL_HANDLE_DESC
};

pub const Driver = struct {
    description: []const u8,
    attributes: []const u8,

    pub fn deinit(self: *Driver, allocator: *std.mem.Allocator) void {
        allocator.free(self.description);
        allocator.free(self.attributes);
    }
};

pub const DataSource = struct {
    server_name: []const u8, description: []const u8
};

pub const DriverCompletion = enum(c_ushort) {
    /// If the user does not provide enough information in the connection string to establish a connection,
    /// return an error.
    NoPrompt = odbc.SQL_DRIVER_NOPROMPT,
    /// If the user does not provide enough information in the connection string to establish a connection,
    /// display a window prompt that will allow them to fill out any other information.
    Complete = odbc.SQL_DRIVER_COMPLETE,
    /// Always prompt the user for connection information, using the values provided in the connection string
    /// as default values.
    Prompt = odbc.SQL_DRIVER_PROMPT,
    /// If the user does not provide enough information in the connection string to establish a connection,
    /// display a window prompt that will allow them to fill out only fields that are required in order to connection.
    CompleteRequired = odbc.SQL_DRIVER_COMPLETE_REQUIRED
};

pub const Direction = enum(c_ushort) {
    /// Fetch the next record in the list. If this is used for the first fetch call, then the first record
    /// will be returned. If `FetchFirstUser` was used before this, then this will get the next user record.
    /// The same is true for `FetchFirstSystem`.
    FetchNext = odbc.SQL_FETCH_NEXT,
    /// Fetch the first record in the list.
    FetchFirst = odbc.SQL_FETCH_FIRST,
    /// Fetch the first user record.
    FetchFirstUser = odbc.SQL_FETCH_FIRST_USER,
    /// Fetch the first system record.
    FetchFirstSystem = odbc.SQL_FETCH_FIRST_SYSTEM
};

pub const DiagnosticIdentifier = enum(odbc.SQLSMALLINT) {
    CursorRowCount = odbc.SQL_DIAG_CURSOR_ROW_COUNT,
    DynamicFunction = odbc.SQL_DIAG_DYNAMIC_FUNCTION,
    DynamicFunctionCode = odbc.SQL_DIAG_DYNAMIC_FUNCTION_CODE,
    Number = odbc.SQL_DIAG_NUMBER,
    ReturnCode = odbc.SQL_DIAG_RETURNCODE,
    RowCount = odbc.SQL_DIAG_ROW_COUNT
};

pub const Nullable = enum(odbc.SQLLEN) {
    Nullable = odbc.SQL_NULLABLE,
    NonNullable = odbc.SQL_NO_NULLS,
    Unknown = odbc.SQL_NULLABLE_UNKNOWN,
};

/// The attributes that can be set or read for an Environment.
pub const EnvironmentAttribute = enum(i32) {
    OdbcVersion = odbc.SQL_ATTR_ODBC_VERSION,
    ConnectionPool = odbc.SQL_ATTR_CONNECTION_POOLING,
    ConnectionPoolMatch = odbc.SQL_ATTR_CP_MATCH,
    OutputNts = odbc.SQL_ATTR_OUTPUT_NTS,

    /// Convert an integer attribute value into a structured AttributeValue. Uses the current active
    /// Attribute to pick the correct union tag, since different attributes use the same underlying values
    /// (i.e. `ConnectionPool.Off == ConnectionPoolMath.Strict`).
    pub fn getAttributeValue(self: EnvironmentAttribute, value: i32) EnvironmentAttributeValue {
        return switch (self) {
            .OdbcVersion => .{ .OdbcVersion = @intToEnum(EnvironmentAttributeValue.OdbcVersion, value) },
            .ConnectionPool => .{ .ConnectionPool = @intToEnum(EnvironmentAttributeValue.ConnectionPool, @intCast(u32, value)) },
            .ConnectionPoolMatch => .{ .ConnectionPoolMatch = @intToEnum(EnvironmentAttributeValue.ConnectionPoolMatch, @intCast(u32, value)) },
            .OutputNts => .{ .OutputNts = value != 0 },
        };
    }
};

/// The set of possible values for different environment attributes.
pub const EnvironmentAttributeValue = union(EnvironmentAttribute) {
    ConnectionPool: ConnectionPool,
    ConnectionPoolMatch: ConnectionPoolMatch,
    OdbcVersion: OdbcVersion,
    OutputNts: bool,

    pub const ConnectionPool = enum(u32) {
        Off = odbc.SQL_CP_OFF,
        OnePerDriver = odbc.SQL_CP_ONE_PER_DRIVER,
        OnePerEnvironment = odbc.SQL_CP_DRIVER_AWARE,
    };

    pub const ConnectionPoolMatch = enum(u32) {
        Strict = odbc.SQL_CP_STRICT_MATCH,
        Relaxed = odbc.SQL_CP_RELAXED_MATCH
    };

    pub const OdbcVersion = enum(i32) {
        Odbc2 = odbc.SQL_OV_ODBC2,
        Odbc3 = odbc.SQL_OV_ODBC3,
        Odbc380 = odbc.SQL_OV_ODBC3_80,
    };

    /// Get the underlying integer value that the current attribute value represents.
    pub fn getValue(self: EnvironmentAttributeValue) u32 {
        const val = switch (self) {
            .ConnectionPool => |v| @enumToInt(v),
            .ConnectionPoolMatch => |v| @enumToInt(v),
            .OdbcVersion => |v| @intCast(u32, @enumToInt(v)),
            .OutputNts => |nts| if (nts) @as(u32, 1) else @as(u32, 0)
        };

        return @intCast(u32, val);
    } 
};

pub const ConnectionAttribute = enum(i32) {
    AccessMode = odbc.SQL_ATTR_ACCESS_MODE,
    AsyncConnectEvent = odbc.SQL_ATTR_ASYNC_DBC_EVENT,
    EnableAsyncConnectFunctions = odbc.SQL_ATTR_ASYNC_DBC_FUNCTIONS_ENABLE,
    EnableAsync = odbc.SQL_ATTR_ASYNC_ENABLE,
    AutoIpd = odbc.SQL_ATTR_AUTO_IPD,
    Autocommit = odbc.SQL_ATTR_AUTOCOMMIT,
    ConnectionDead = odbc.SQL_ATTR_CONNECTION_DEAD,
    ConnectionTimeout = odbc.SQL_ATTR_CONNECTION_TIMEOUT,
    CurrentCatalog = odbc.SQL_ATTR_CURRENT_CATALOG,
    EnlistInDtc = odbc.SQL_ATTR_ENLIST_IN_DTC,
    LoginTimeout = odbc.SQL_ATTR_LOGIN_TIMEOUT,
    MetadataId = odbc.SQL_ATTR_METADATA_ID,
    OdbcCursors = odbc.SQL_ATTR_ODBC_CURSORS,
    PacketSize = odbc.SQL_ATTR_PACKET_SIZE,
    QuietMode = odbc.SQL_ATTR_QUIET_MODE,
    Trace = odbc.SQL_ATTR_TRACE,
    Tracefile = odbc.SQL_ATTR_TRACEFILE,
    TranslateLib = odbc.SQL_ATTR_TRANSLATE_LIB,
    TranslateOption = odbc.SQL_ATTR_TRANSLATE_OPTION,
    TransactionIsolation = odbc.SQL_ATTR_TXN_ISOLATION,

    pub fn getAttributeValue(comptime self: ConnectionAttribute, bytes: []u8) ConnectionAttributeValue {
        return unionInitEnum(ConnectionAttributeValue, self, switch (self) {
            .AccessMode => @intToEnum(ConnectionAttributeValue.AccessMode, sliceToValue(u32, bytes)),
            .AsyncConnectEvent => sliceToValue(odbc.SQLPOINTER, bytes),
            .EnableAsyncConnectFunctions => sliceToValue(u32, bytes) == odbc.SQL_ASYNC_DBC_ENABLE_ON,
            .EnableAsync => sliceToValue(usize, bytes) == odbc.SQL_ASYNC_ENABLE_ON,
            .AutoIpd => sliceToValue(u32, bytes) == odbc.SQL_TRUE,
            .Autocommit => sliceToValue(u32, bytes) == odbc.SQL_AUTOCOMMIT_ON,
            .ConnectionDead => sliceToValue(u32, bytes) == odbc.SQL_CD_TRUE,
            .ConnectionTimeout => sliceToValue(u32, bytes),
            .CurrentCatalog => bytes,
            .EnlistInDtc => sliceToValue(odbc.SQLPOINTER, bytes),
            .LoginTimeout => sliceToValue(u32, bytes),
            .MetadataId => sliceToValue(u32, bytes) == odbc.SQL_TRUE,
            .OdbcCursors => @intToEnum(ConnectionAttributeValue.OdbcCursors, sliceToValue(usize, bytes)),
            .PacketSize => sliceToValue(u32, bytes),
            .QuietMode => sliceToValue(odbc.HWND, bytes),
            .Trace => sliceToValue(u32, bytes) == odbc.SQL_OPT_TRACE_ON,
            .Tracefile => bytes[0..:0],
            .TranslateLib => bytes[0..:0],
            .TranslateOption => sliceToValue(u32, bytes),
            .TransactionIsolation => sliceToValue(u32, bytes),
        });
    }
};

pub const ConnectionAttributeValue = union(ConnectionAttribute) {
    AccessMode: AccessMode,
    AsyncConnectEvent: odbc.SQLPOINTER,
    EnableAsyncConnectFunctions: bool,
    EnableAsync: bool,
    AutoIpd: bool,
    Autocommit: bool,
    ConnectionDead: bool,
    ConnectionTimeout: u32,
    CurrentCatalog: []u8,
    EnlistInDtc: odbc.SQLPOINTER,
    LoginTimeout: u32,
    MetadataId: bool,
    OdbcCursors: OdbcCursors,
    PacketSize: u32,
    QuietMode: odbc.HWND,
    Trace: bool,
    Tracefile: [:0] u8,
    TranslateLib: [:0]u8,
    TranslateOption: u32,
    TransactionIsolation: u32,

    pub const AccessMode = enum(u32) {
        ReadOnly = odbc.SQL_MODE_READ_ONLY,
        ReadWrite = odbc.SQL_MODE_READ_WRITE
    };

    pub const OdbcCursors = enum(usize) {
        UseOdbc = odbc.SQL_CUR_USE_ODBC,
        UseIfNeeded = odbc.SQL_CUR_USE_IF_NEEDED,
        UseDriver = odbc.SQL_CUR_USE_DRIVER
    };

    pub fn getValue(self: ConnectionAttributeValue, allocator: *std.mem.Allocator) ![]u8 {
        const value_buffer: []u8 = switch (self) {
            .AccessMode => |v| toBytes(@enumToInt(v))[0..],
            .AsyncConnectEvent => |v| toBytes(@ptrToInt(v))[0..],
            .EnableAsyncConnectFunctions => |v| if (v) toBytes(@as(u32, odbc.SQL_ASYNC_DBC_ENABLE_ON))[0..] else toBytes(@as(u32, odbc.SQL_ASYNC_DBC_ENABLE_OFF))[0..],  
            .EnableAsync => |v| if (v) toBytes(@as(usize, odbc.SQL_ASYNC_ENABLE_ON))[0..] else toBytes(@as(usize, odbc.SQL_ASYNC_ENABLE_OFF))[0..],
            .AutoIpd => |v| if (v) toBytes(@as(u32, odbc.SQL_TRUE))[0..] else toBytes(@as(u32, odbc.SQL_FALSE))[0..],
            .Autocommit => |v| blk: {
                const sql_val: u32 = if (v) odbc.SQL_AUTOCOMMIT_ON else odbc.SQL_AUTOCOMMIT_OFF;
                break :blk toBytes(sql_val)[0..];
            },
            .ConnectionDead => |v| if (v) toBytes(@as(u32, odbc.SQL_CD_TRUE))[0..] else toBytes(@as(u32, odbc.SQL_CD_FALSE))[0..],
            .ConnectionTimeout => |v| toBytes(v)[0..],
            .CurrentCatalog => |v| v,
            .EnlistInDtc => |v| toBytes(@ptrToInt(v))[0..],
            .LoginTimeout => |v| toBytes(v)[0..],
            .MetadataId => |v| if (v) toBytes(@as(u32, odbc.SQL_TRUE))[0..] else toBytes(@as(u32, odbc.SQL_FALSE))[0..],
            .OdbcCursors => |v| toBytes(@enumToInt(v))[0..],
            .PacketSize => |v| toBytes(v)[0..],
            .QuietMode => |v| toBytes(@ptrToInt(v))[0..],
            .Trace => |v| if (v) toBytes(@as(u32, odbc.SQL_OPT_TRACE_ON))[0..] else toBytes(@as(u32, odbc.SQL_OPT_TRACE_OFF))[0..],
            .Tracefile => |v| v,
            .TranslateLib => |v| v,
            .TranslateOption => |v| toBytes(v)[0..],
            .TransactionIsolation => |v| toBytes(v)[0..]
        };

        const result_buffer = try allocator.alloc(u8, value_buffer.len);
        std.mem.copy(u8, result_buffer, value_buffer);
        return result_buffer;
    }

};

pub const FunctionId = enum(c_ushort) {
    usingnamespace odbc;
    // ISO 92 standards-compliance level
    SQLAllocHandle = SQL_API_SQLALLOCHANDLE,
    SQLBindCol = SQL_API_SQLBINDCOL,
    SQLCancel = SQL_API_SQLCANCEL,
    SQLCloseCursor = SQL_API_SQLCLOSECURSOR,
    SQLColAttribue = SQL_API_SQLCOLATTRIBUTE,
    SQLConnect = SQL_API_SQLCONNECT,
    SQLCopyDesc = SQL_API_SQLCOPYDESC,
    SQLDataSources = SQL_API_SQLDATASOURCES,
    SQLDescribeCol = SQL_API_SQLDESCRIBECOL,
    SQLDisconnect = SQL_API_SQLDISCONNECT,
    SQLDrivers = SQL_API_SQLDRIVERS,
    SQLEndTran = SQL_API_SQLENDTRAN,
    SQLExecDirect = SQL_API_SQLEXECDIRECT,
    SQLExecute = SQL_API_SQLEXECUTE,
    SQLFetch = SQL_API_SQLFETCH,
    SQLFetchScroll = SQL_API_SQLFETCHSCROLL,
    SQLFreeHandle = SQL_API_SQLFREEHANDLE,
    SQLFreeStmt = SQL_API_SQLFREESTMT,
    SQLGetConnectAttr = SQL_API_SQLGETCONNECTATTR,
    SQLGetCursorName = SQL_API_SQLGETCURSORNAME,
    SQLGetData = SQL_API_SQLGETDATA,
    SQLGetDescField = SQL_API_SQLGETDESCFIELD,
    SQLGetDescRec = SQL_API_SQLGETDESCREC,
    SQLGetDiagField = SQL_API_SQLGETDIAGFIELD,
    SQLGetDiagRec = SQL_API_SQLGETDIAGREC,
    SQLGetEnvAttr = SQL_API_SQLGETENVATTR,
    SQLGetFunctions = SQL_API_SQLGETFUNCTIONS,
    SQLGetInfo = SQL_API_SQLGETINFO,
    SQLGetStmtAttr = SQL_API_SQLGETSTMTATTR,
    SQLGetTypeInfo = SQL_API_SQLGETTYPEINFO,
    SQLNumResultCols = SQL_API_SQLNUMRESULTCOLS,
    SQLParamData = SQL_API_SQLPARAMDATA,
    SQLPrepare = SQL_API_SQLPREPARE,
    SQLPutData = SQL_API_SQLPUTDATA,
    SQLRowCount = SQL_API_SQLROWCOUNT,
    SQLSetConnectAttr = SQL_API_SQLSETCONNECTATTR,
    SQLSetCursorName = SQL_API_SQLSETCURSORNAME,
    SQLSetDescField = SQL_API_SQLSETDESCFIELD,
    SQLSetDescRec = SQL_API_SQLSETDESCREC,
    SQLSetEnvAttr = SQL_API_SQLSETENVATTR,
    SQLSetStmtAttr = SQL_API_SQLSETSTMTATTR,
    // Open Groups standards-compliance level
    SQLColumns = SQL_API_SQLCOLUMNS,
    SQLSpecialColumns = SQL_API_SQLSPECIALCOLUMNS,
    SQLStatistics = SQL_API_SQLSTATISTICS,
    SQLTables = SQL_API_SQLTABLES,
    // ODBC standards-compliance level
    SQLBindParameter = SQL_API_SQLBINDPARAMETER,
    SQLBrowseConnect = SQL_API_SQLBROWSECONNECT,
    SQLBulkOperations = SQL_API_SQLBULKOPERATIONS,
    SQLColumnPrivileges = SQL_API_SQLCOLUMNPRIVILEGES,
    SQLDescribeParam = SQL_API_SQLDESCRIBEPARAM,
    SQLDriverConnect = SQL_API_SQLDRIVERCONNECT,
    SQLForeignKeys = SQL_API_SQLFOREIGNKEYS,
    SQLMoreResults = SQL_API_SQLMORERESULTS, 
    SQLNativeSql = SQL_API_SQLNATIVESQL,
    SQLNumParams = SQL_API_SQLNUMPARAMS,
    SQLPrimaryKeys = SQL_API_SQLPRIMARYKEYS,
    SQLProcedureColumns = SQL_API_SQLPROCEDURECOLUMNS,
    SQLProcedures = SQL_API_SQLPROCEDURES,
    SQLSetPos = SQL_API_SQLSETPOS,
    SQLTablePrivileges = SQL_API_SQLTABLEPRIVILEGES,
};

/// Information types that are used with Connection.getInfo
pub const InformationType = enum(c_ushort) {
    usingnamespace odbc;
    ActiveEnvironments = SQL_ACTIVE_ENVIRONMENTS,
    AsyncConnectFunctions = SQL_ASYNC_DBC_FUNCTIONS,
    AsyncMode = SQL_ASYNC_MODE,
    AsyncNotification = SQL_ASYNC_NOTIFICATION,
    BatchRowCount = SQL_BATCH_ROW_COUNT,
    BatchSupport = SQL_BATCH_SUPPORT,
    DataSourceName = SQL_DATA_SOURCE_NAME,
    DriverAwarePoolingSupported = SQL_DRIVER_AWARE_POOLING_SUPPORTED,
    DriverConnectionHandle = SQL_DRIVER_HDBC,
    DriverDescriptorHandle = SQL_DRIVER_HDESC,
    DriverEnvironmentHandle = SQL_DRIVER_HENV,
    DriverLibraryHandle = SQL_DRIVER_HLIB,
    DriverStatementHandle = SQL_DRIVER_HSTMT,
    DriverName = SQL_DRIVER_NAME,
    DriverOdbcVersion = SQL_DRIVER_ODBC_VER,
    DriverVersion = SQL_DRIVER_VER,
    DynamicCursorAttributes1 = SQL_DYNAMIC_CURSOR_ATTRIBUTES1,
    DynamicCursorAttributes2 = SQL_DYNAMIC_CURSOR_ATTRIBUTES2,
    ForwardOnlyCursorAttributes1 = SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1,
    ForwardOnlyCursorAttributes2 = SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2,
    FileUsage = SQL_FILE_USAGE,
    GetDataExtensions = SQL_GETDATA_EXTENSIONS,
    InfoSchemaViews = SQL_INFO_SCHEMA_VIEWS,
    KeysetCursorAttributes1 = SQL_KEYSET_CURSOR_ATTRIBUTES1,
    KeysetCursorAttributes2 = SQL_KEYSET_CURSOR_ATTRIBUTES2,
    MaxAsyncConcurrentStatements = SQL_MAX_ASYNC_CONCURRENT_STATEMENTS,
    MaxConcurrentActivities = SQL_MAX_CONCURRENT_ACTIVITIES,
    MaxDriverConnections = SQL_MAX_DRIVER_CONNECTIONS,
    OdbcInterfaceConformance = SQL_ODBC_INTERFACE_CONFORMANCE,
    OdbcVersion = SQL_ODBC_VER,
    ParamArrayRowCounts = SQL_PARAM_ARRAY_ROW_COUNTS,
    ParamArraySelects = SQL_PARAM_ARRAY_SELECTS,
    RowUpdates = SQL_ROW_UPDATES,
    SearchPatternEscape = SQL_SEARCH_PATTERN_ESCAPE,
    ServerName = SQL_SERVER_NAME,
    StaticCursorAttributes1 = SQL_STATIC_CURSOR_ATTRIBUTES1,
    StaticCursorAttributes2 = SQL_STATIC_CURSOR_ATTRIBUTES2,
    // DBMS Product Information
    DatabaseName = SQL_DATABASE_NAME, 
    DBMSName = SQL_DBMS_NAME, 
    DBMSVersion = SQL_DBMS_VER,
    // Data Source Information 
    AccessibleProcedures = SQL_ACCESSIBLE_PROCEDURES,
    AccessibleTables = SQL_ACCESSIBLE_TABLES,
    BookmarkPersistence = SQL_BOOKMARK_PERSISTENCE,
    CatalogTerm = SQL_CATALOG_TERM,
    CollationSeq = SQL_COLLATION_SEQ,
    ConcatNullBehavior = SQL_CONCAT_NULL_BEHAVIOR,
    CursorCommitBehavior = SQL_CURSOR_COMMIT_BEHAVIOR,
    CursorRollbackBehavior = SQL_CURSOR_ROLLBACK_BEHAVIOR,
    CursorSensitivity = SQL_CURSOR_SENSITIVITY,
    DataSourceReadOnly = SQL_DATA_SOURCE_READ_ONLY,
    DefaultTransactionIsolation = SQL_DEFAULT_TXN_ISOLATION,
    DescribeParameter = SQL_DESCRIBE_PARAMETER,
    MultipleResultSets = SQL_MULT_RESULT_SETS,
    MultipleActiveTransactions = SQL_MULTIPLE_ACTIVE_TXN,
    NeedLongDataLength = SQL_NEED_LONG_DATA_LEN,
    NullCollation = SQL_NULL_COLLATION,
    ProcedureTerm = SQL_PROCEDURE_TERM,
    SchemaTerm = SQL_SCHEMA_TERM,
    ScrollOptions = SQL_SCROLL_OPTIONS,
    TableTerm = SQL_TABLE_TERM,
    TransactionCapable = SQL_TXN_CAPABLE,
    TransactionIsolationOption = SQL_TXN_ISOLATION_OPTION,
    Username = SQL_USER_NAME,
    // Supported SQL
    AggregateFunctions = SQL_AGGREGATE_FUNCTIONS,
    AlterDomain = SQL_ALTER_DOMAIN,
    AlterTable = SQL_ALTER_TABLE,
    DatetimeLiterals = SQL_DATETIME_LITERALS,
    CatalogLocation = SQL_CATALOG_LOCATION,
    CatalogName = SQL_CATALOG_NAME,
    CatalogNameSeparator = SQL_CATALOG_NAME_SEPARATOR,
    CatalogUsage = SQL_CATALOG_USAGE,
    ColumnAlias = SQL_COLUMN_ALIAS,
    CorrelationName = SQL_CORRELATION_NAME,
    CreateAssertion = SQL_CREATE_ASSERTION,
    CreateCharacterSet = SQL_CREATE_CHARACTER_SET,
    CreateCollation = SQL_CREATE_COLLATION,
    CreateDomain = SQL_CREATE_DOMAIN,
    CreateSchema = SQL_CREATE_SCHEMA,
    CreateTable = SQL_CREATE_TABLE,
    CreateTranslation = SQL_CREATE_TRANSLATION,
    CreateView = SQL_CREATE_VIEW,
    DDLIndex = SQL_DDL_INDEX,
    DropAssertion = SQL_DROP_ASSERTION,
    DropCharacterSet = SQL_DROP_CHARACTER_SET,
    DropCollation = SQL_DROP_COLLATION,
    DropDomain = SQL_DROP_DOMAIN,
    DropSchema = SQL_DROP_SCHEMA,
    DropTable = SQL_DROP_TABLE,
    DropTranslation = SQL_DROP_TRANSLATION,
    DropView = SQL_DROP_VIEW,
    ExpressionsInOrderBy = SQL_EXPRESSIONS_IN_ORDERBY,
    GroupBy = SQL_GROUP_BY,
    IdentifierCase = SQL_IDENTIFIER_CASE,
    IdentifierQuoteChar = SQL_IDENTIFIER_QUOTE_CHAR,
    IndexKeywords = SQL_INDEX_KEYWORDS,
    InsertStatement = SQL_INSERT_STATEMENT,
    Integrity = SQL_INTEGRITY,
    Keywords = SQL_KEYWORDS,
    LikeEscapeClause = SQL_LIKE_ESCAPE_CLAUSE,
    NonNullableColumns = SQL_NON_NULLABLE_COLUMNS,
    OJCapabilities = SQL_OJ_CAPABILITIES,
    OrderByColumnsInSelect = SQL_ORDER_BY_COLUMNS_IN_SELECT,
    Procedures = SQL_PROCEDURES,
    QuotedIdentifierCase = SQL_QUOTED_IDENTIFIER_CASE,
    SchemaUsage = SQL_SCHEMA_USAGE,
    SpecialCharacters = SQL_SPECIAL_CHARACTERS,
    SQLConformance = SQL_SQL_CONFORMANCE,
    SQLSubqueries = SQL_SUBQUERIES,
    Union = SQL_UNION,
    // SQL Limits
    MaxBinaryLiteralLength = SQL_MAX_BINARY_LITERAL_LEN,
    MaxCatalogNameLength = SQL_MAX_CATALOG_NAME_LEN,
    MaxCharLiteralLength = SQL_MAX_CHAR_LITERAL_LEN,
    MaxColumnNameLength = SQL_MAX_COLUMN_NAME_LEN,
    MaxColumnsInGroupBy = SQL_MAX_COLUMNS_IN_GROUP_BY,
    MaxColumnsInIndex = SQL_MAX_COLUMNS_IN_INDEX,
    MaxColumnsInOrderBy = SQL_MAX_COLUMNS_IN_ORDER_BY,
    MaxColumnsInSelect = SQL_MAX_COLUMNS_IN_SELECT,
    MaxColumnsInTable = SQL_MAX_COLUMNS_IN_TABLE,
    MaxCursorNameLength = SQL_MAX_CURSOR_NAME_LEN,
    MaxIdentifierLength = SQL_MAX_IDENTIFIER_LEN,
    MaxIndexSize = SQL_MAX_INDEX_SIZE,
    MaxProcedureNameLength = SQL_MAX_PROCEDURE_NAME_LEN,
    MaxRowSize = SQL_MAX_ROW_SIZE,
    MaxRowSizeIncludesLong = SQL_MAX_ROW_SIZE_INCLUDES_LONG,
    MaxSchemaNameLength = SQL_MAX_SCHEMA_NAME_LEN,
    MaxStatementLength = SQL_MAX_STATEMENT_LEN,
    MaxTableNameLength = SQL_MAX_TABLE_NAME_LEN,
    MaxTablesInSelect = SQL_MAX_TABLES_IN_SELECT,
    MaxUserNameLength = SQL_MAX_USER_NAME_LEN,
    // Scalar Function Information 
    ConvertFunctions = SQL_CONVERT_FUNCTIONS,
    NumericFunctions = SQL_NUMERIC_FUNCTIONS,
    StringFunctions = SQL_STRING_FUNCTIONS,
    SystemFunctions = SQL_SYSTEM_FUNCTIONS,
    TimeDateAddIntervals = SQL_TIMEDATE_ADD_INTERVALS,
    TimeDateDiffIntervals = SQL_TIMEDATE_DIFF_INTERVALS,
    TimeDateFunctions = SQL_TIMEDATE_FUNCTIONS,
    // Conversion Information
    ConvertBigint = SQL_CONVERT_BIGINT,
    ConvertBinary = SQL_CONVERT_BINARY,
    ConvertBit = SQL_CONVERT_BIT,
    ConvertChar = SQL_CONVERT_CHAR,
    ConvertDate = SQL_CONVERT_DATE,
    ConvertDecimal = SQL_CONVERT_DECIMAL,
    ConvertDouble = SQL_CONVERT_DOUBLE,
    ConvertFloat = SQL_CONVERT_FLOAT,
    ConvertInteger = SQL_CONVERT_INTEGER,
    ConvertIntervalDayTime = SQL_CONVERT_INTERVAL_DAY_TIME,
    ConvertIntervalYearMonth = SQL_CONVERT_INTERVAL_YEAR_MONTH,
    ConvertLongVarBinary = SQL_CONVERT_LONGVARBINARY,
    ConvertLongVarChar = SQL_CONVERT_LONGVARCHAR,
    ConvertNumeric = SQL_CONVERT_NUMERIC,
    ConvertReal = SQL_CONVERT_REAL,
    ConvertSmallInt = SQL_CONVERT_SMALLINT,
    ConvertTime = SQL_CONVERT_TIME,
    ConvertTimestamp = SQL_CONVERT_TIMESTAMP,
    ConvertTinyInt = SQL_CONVERT_TINYINT,
    ConvertVarBinary = SQL_CONVERT_VARBINARY,
    ConvertVarChar = SQL_CONVERT_VARCHAR,
    // Information types added for odbc 3.x
    DMVersion = SQL_DM_VER,
    XOpenCliYear = SQL_XOPEN_CLI_YEAR,
    // Information types deprecated in odbc 3.x, but must still be supported
    PosOperations = SQL_POS_OPERATIONS,

    pub fn getValue(comptime self: InformationType, bytes: []u8, string_len: usize) InformationTypeValue {
        return unionInitEnum(InformationTypeValue, self, switch (self) {
            // Assorted bitmask attributes
            .BatchRowCount => InformationTypeValue.BatchRowCount.applyBitmask(sliceToValue(u32, bytes)),
            .BatchSupport => InformationTypeValue.BatchSupport.applyBitmask(sliceToValue(u32, bytes)),
            .GetDataExtensions => InformationTypeValue.GetDataExtensions.applyBitmask(sliceToValue(u32, bytes)),
            .InfoSchemaViews => InformationTypeValue.InfoSchemaViews.applyBitmask(sliceToValue(u32, bytes)),
            .ParamArraySelects => InformationTypeValue.ParamArraySelects.applyBitmask(sliceToValue(u32, bytes)),
            .BookmarkPersistence => InformationTypeValue.BookmarkPersistence.applyBitmask(sliceToValue(u32, bytes)),
            .DefaultTransactionIsolation => InformationTypeValue.DefaultTransactionIsolation.applyBitmask(sliceToValue(u32, bytes)),
            .ScrollOptions => InformationTypeValue.ScrollOptions.applyBitmask(sliceToValue(u32, bytes)),
            .TransactionCapable => InformationTypeValue.TransactionCapable.applyBitmask(sliceToValue(u32, bytes)),
            .TransactionIsolationOption => InformationTypeValue.TransactionIsolationOptions.applyBitmask(sliceToValue(u32, bytes)),
            .AggregateFunctions => InformationTypeValue.AggregateFunctions.applyBitmask(sliceToValue(u32, bytes)),
            .AlterDomain => InformationTypeValue.AlterDomain.applyBitmask(sliceToValue(u32, bytes)),
            .AlterTable => InformationTypeValue.AlterTable.applyBitmask(sliceToValue(u32, bytes)),
            .DatetimeLiterals => InformationTypeValue.DatetimeLiterals.applyBitmask(sliceToValue(u32, bytes)),
            .CatalogUsage => InformationTypeValue.CatalogUsage.applyBitmask(sliceToValue(u32, bytes)),
            .CreateAssertion => InformationTypeValue.CreateAssertion.applyBitmask(sliceToValue(u32, bytes)),
            .CreateCharacterSet => InformationTypeValue.CreateCharacterSet.applyBitmask(sliceToValue(u32, bytes)),
            .CreateCollation => InformationTypeValue.CreateCollation.applyBitmask(sliceToValue(u32, bytes)),
            .CreateDomain => InformationTypeValue.CreateDomain.applyBitmask(sliceToValue(u32, bytes)),
            .CreateSchema => InformationTypeValue.CreateSchema.applyBitmask(sliceToValue(u32, bytes)),
            .CreateTable => InformationTypeValue.CreateTable.applyBitmask(sliceToValue(u32, bytes)),
            .CreateTranslation => InformationTypeValue.CreateTranslation.applyBitmask(sliceToValue(u32, bytes)),
            .CreateView => InformationTypeValue.CreateView.applyBitmask(sliceToValue(u32, bytes)),
            .DDLIndex => InformationTypeValue.DDLIndex.applyBitmask(sliceToValue(u32, bytes)),
            .DropAssertion => InformationTypeValue.DropAssertion.applyBitmask(sliceToValue(u32, bytes)),
            .DropCharacterSet => InformationTypeValue.DropCharacterSet.applyBitmask(sliceToValue(u32, bytes)),
            .DropCollation => InformationTypeValue.DropCollation.applyBitmask(sliceToValue(u32, bytes)),
            .DropDomain => InformationTypeValue.DropDomain.applyBitmask(sliceToValue(u32, bytes)),
            .DropSchema => InformationTypeValue.DropSchema.applyBitmask(sliceToValue(u32, bytes)),
            .DropTable => InformationTypeValue.DropTable.applyBitmask(sliceToValue(u32, bytes)),
            .DropTranslation => InformationTypeValue.DropTranslation.applyBitmask(sliceToValue(u32, bytes)),
            .DropView => InformationTypeValue.DropView.applyBitmask(sliceToValue(u32, bytes)),
            .IndexKeywords => InformationTypeValue.IndexKeywords.applyBitmask(sliceToValue(u32, bytes)),
            .InsertStatement => InformationTypeValue.InsertStatement.applyBitmask(sliceToValue(u32, bytes)),
            .OJCapabilities => InformationTypeValue.OJCapabilities.applyBitmask(sliceToValue(u32, bytes)),
            .SchemaUsage => InformationTypeValue.SchemaUsage.applyBitmask(sliceToValue(u32, bytes)),
            .SQLSubqueries => InformationTypeValue.Subqueries.applyBitmask(sliceToValue(u32, bytes)),
            .Union => InformationTypeValue.Union.applyBitmask(sliceToValue(u32, bytes)),
            .ConvertFunctions => InformationTypeValue.ConvertFunctions.applyBitmask(sliceToValue(u32, bytes)),
            .NumericFunctions => InformationTypeValue.NumericFunctions.applyBitmask(sliceToValue(u32, bytes)),
            .StringFunctions => InformationTypeValue.StringFunctions.applyBitmask(sliceToValue(u32, bytes)),
            .SystemFunctions => InformationTypeValue.SystemFunctions.applyBitmask(sliceToValue(u32, bytes)),
            .PosOperations => InformationTypeValue.PositionOperations.applyBitmask(sliceToValue(c_ushort, bytes)),
            .TimeDateFunctions => InformationTypeValue.TimedateFunctions.applyBitmask(sliceToValue(u32, bytes)),
            // Cursor Attributes bitmask attributes
            .DynamicCursorAttributes1, .ForwardOnlyCursorAttributes1, 
            .KeysetCursorAttributes1, .StaticCursorAttributes1 => InformationTypeValue.CursorAttributes1.applyBitmask(sliceToValue(u32, bytes)),
            .DynamicCursorAttributes2, .ForwardOnlyCursorAttributes2,
            .KeysetCursorAttributes2, .StaticCursorAttributes2 => InformationTypeValue.CursorAttributes2.applyBitmask(sliceToValue(u32, bytes)),
            // TimeDate interval bitmask attributes.
            .TimeDateAddIntervals, .TimeDateDiffIntervals => InformationTypeValue.TimedateIntervals.applyBitmask(sliceToValue(u32, bytes)),
            // Supported conversions bitmask attributes
            .ConvertBigint, .ConvertBinary, .ConvertBit,
            .ConvertChar, .ConvertDate, .ConvertDecimal, .ConvertDouble, .ConvertFloat, .ConvertInteger,
            .ConvertIntervalDayTime, .ConvertIntervalYearMonth, .ConvertLongVarBinary, .ConvertLongVarChar, .ConvertNumeric,
            .ConvertReal, .ConvertSmallInt, .ConvertTime, .ConvertTimestamp, .ConvertTinyInt, .ConvertVarBinary,
            .ConvertVarChar => InformationTypeValue.SupportedConversion.applyBitmask(sliceToValue(u32, bytes)),
            // Assorted enum attributes
            .AsyncMode => @intToEnum(InformationTypeValue.AsyncMode, sliceToValue(u32, bytes)),
            .FileUsage => @intToEnum(InformationTypeValue.FileUsage, sliceToValue(c_ushort, bytes)),
            .OdbcInterfaceConformance => @intToEnum(InformationTypeValue.InterfaceConformance, sliceToValue(c_ushort, bytes)),
            .ConcatNullBehavior => @intToEnum(InformationTypeValue.ConcatNullBehavior, sliceToValue(c_ushort, bytes)),
            .CursorCommitBehavior => @intToEnum(InformationTypeValue.CursorCommitBehavior, sliceToValue(c_ushort, bytes)),
            .CursorRollbackBehavior => @intToEnum(InformationTypeValue.CursorRollbackBehavior, sliceToValue(c_ushort, bytes)),
            .CursorSensitivity => @intToEnum(InformationTypeValue.CursorSensitivity, sliceToValue(c_ushort, bytes)),
            .NullCollation => @intToEnum(InformationTypeValue.NullCollation, sliceToValue(c_ushort, bytes)),
            .CatalogLocation => @intToEnum(InformationTypeValue.CatalogLocation, sliceToValue(c_ushort, bytes)),
            .CorrelationName => @intToEnum(InformationTypeValue.CorrelationName, sliceToValue(c_ushort, bytes)),
            .GroupBy => @intToEnum(InformationTypeValue.GroupBy, sliceToValue(c_ushort, bytes)),
            .IdentifierCase => @intToEnum(InformationTypeValue.IdentifierCase, sliceToValue(c_ushort, bytes)),
            .QuotedIdentifierCase => @intToEnum(InformationTypeValue.QuotedIdentifierCase, sliceToValue(c_ushort, bytes)),
            .SQLConformance => @intToEnum(InformationTypeValue.SQLConformance, sliceToValue(c_ushort, bytes)),
            // String attributes
            .DataSourceName, .DriverName, .DriverOdbcVersion, 
            .DriverVersion, .OdbcVersion, .SearchPatternEscape, 
            .ServerName, .DatabaseName, .DBMSName, 
            .DBMSVersion, .CatalogTerm, .CollationSeq, 
            .ProcedureTerm, .SchemaTerm, .TableTerm,
            .Username, .CatalogNameSeparator, .IdentifierQuoteChar, 
            .Keywords, .DMVersion, .XOpenCliYear,
            .SpecialCharacters => bytes[0..string_len:0],
            // Boolean attributes
            .AccessibleProcedures, .AccessibleTables, .AsyncConnectFunctions, 
            .AsyncNotification, .DriverAwarePoolingSupported, .ParamArrayRowCounts, .RowUpdates,
            .DataSourceReadOnly, .DescribeParameter, .MultipleResultSets, .MultipleActiveTransactions,
            .NeedLongDataLength, .CatalogName, .ColumnAlias, .ExpressionsInOrderBy, .Integrity,
            .LikeEscapeClause, .NonNullableColumns, .OrderByColumnsInSelect, .Procedures,
            .MaxRowSizeIncludesLong => bytes[0] == 'Y',
            // usize attributes
            .DriverConnectionHandle, .DriverDescriptorHandle, 
            .DriverEnvironmentHandle, .DriverLibraryHandle,
            .DriverStatementHandle => sliceToValue(usize, bytes),
            // u32 attributes
            .MaxAsyncConcurrentStatements, .MaxBinaryLiteralLength, .MaxCharLiteralLength => sliceToValue(u32, bytes),
            // c_ushort attributes
            .ActiveEnvironments, .MaxConcurrentActivities, 
            .MaxDriverConnections, .MaxCatalogNameLength, .MaxColumnNameLength, 
            .MaxColumnsInGroupBy, .MaxColumnsInIndex,
            .MaxColumnsInOrderBy, .MaxColumnsInSelect, 
            .MaxColumnsInTable, .MaxCursorNameLength, .MaxIdentifierLength, 
            .MaxIndexSize, .MaxProcedureNameLength, .MaxRowSize,
            .MaxSchemaNameLength, .MaxStatementLength, 
            .MaxTableNameLength, .MaxTablesInSelect, .MaxUserNameLength => sliceToValue(c_ushort, bytes),
        });
    }


};

pub const InformationTypeValue = union(InformationType) { 
    AccessibleProcedures: bool,
    AccessibleTables: bool,
    ActiveEnvironments: c_ushort,
    AggregateFunctions: AggregateFunctions.Result,
    AlterDomain: AlterDomain.Result,
    AlterTable: AlterTable.Result,
    AsyncConnectFunctions: bool,
    AsyncMode: AsyncMode,
    AsyncNotification: bool,
    BatchRowCount: BatchRowCount.Result,
    BatchSupport: BatchSupport.Result,
    BookmarkPersistence: BookmarkPersistence.Result,
    CatalogLocation: CatalogLocation,
    CatalogName: bool,
    CatalogNameSeparator: [:0]const u8,
    CatalogTerm: [:0]const u8,
    CatalogUsage: CatalogUsage.Result,
    CollationSeq: [:0]const u8,
    ColumnAlias: bool,
    ConcatNullBehavior: ConcatNullBehavior,
    ConvertBigint: SupportedConversion.Result,
    ConvertBinary: SupportedConversion.Result,
    ConvertBit: SupportedConversion.Result,
    ConvertChar: SupportedConversion.Result,
    ConvertDate: SupportedConversion.Result,
    ConvertDecimal: SupportedConversion.Result,
    ConvertDouble: SupportedConversion.Result,
    ConvertFloat: SupportedConversion.Result,
    ConvertInteger: SupportedConversion.Result,
    ConvertIntervalDayTime: SupportedConversion.Result,
    ConvertIntervalYearMonth: SupportedConversion.Result,
    ConvertLongVarBinary: SupportedConversion.Result,
    ConvertLongVarChar: SupportedConversion.Result,
    ConvertNumeric: SupportedConversion.Result,
    ConvertReal: SupportedConversion.Result,
    ConvertSmallInt: SupportedConversion.Result,
    ConvertTime: SupportedConversion.Result,
    ConvertTimestamp: SupportedConversion.Result,
    ConvertTinyInt: SupportedConversion.Result,
    ConvertVarBinary: SupportedConversion.Result,
    ConvertVarChar: SupportedConversion.Result,
    ConvertFunctions: ConvertFunctions.Result, 
    CorrelationName: CorrelationName,
    CreateAssertion: CreateAssertion.Result,
    CreateCharacterSet: CreateCharacterSet.Result,
    CreateCollation: CreateCollation.Result,
    CreateDomain: CreateDomain.Result,
    CreateSchema: CreateSchema.Result,
    CreateTable: CreateTable.Result,
    CreateTranslation: CreateTranslation.Result,
    CreateView: CreateView.Result,
    CursorCommitBehavior: CursorCommitBehavior,
    CursorRollbackBehavior: CursorRollbackBehavior,
    CursorSensitivity: CursorSensitivity,
    DataSourceName: [:0]const u8,
    DataSourceReadOnly: bool,
    DatabaseName: [:0]const u8,
    DatetimeLiterals: DatetimeLiterals.Result,
    DBMSName: [:0]const u8, 
    DBMSVersion: [:0]const u8,
    DDLIndex: DDLIndex.Result,
    DefaultTransactionIsolation: DefaultTransactionIsolation.Result,
    DescribeParameter: bool,
    DMVersion: [:0]const u8,
    DriverAwarePoolingSupported: bool,
    DriverConnectionHandle: usize,
    DriverDescriptorHandle: usize,
    DriverEnvironmentHandle: usize,
    DriverLibraryHandle: usize,
    DriverStatementHandle: usize,
    DriverName: [:0]const u8,
    DriverOdbcVersion: [:0]const u8,
    DriverVersion: [:0]const u8,
    DropAssertion: DropAssertion.Result,
    DropCharacterSet: DropCharacterSet.Result,
    DropCollation: DropCollation.Result,
    DropDomain: DropDomain.Result,
    DropSchema: DropSchema.Result,
    DropTable: DropTable.Result,
    DropTranslation: DropTranslation.Result,
    DropView: DropView.Result,
    DynamicCursorAttributes1: CursorAttributes1.Result,
    DynamicCursorAttributes2: CursorAttributes2.Result,
    ExpressionsInOrderBy: bool,
    FileUsage: FileUsage,
    ForwardOnlyCursorAttributes1: CursorAttributes1.Result,
    ForwardOnlyCursorAttributes2: CursorAttributes2.Result,
    GetDataExtensions: GetDataExtensions.Result,
    GroupBy: GroupBy,
    IdentifierCase: IdentifierCase,
    IdentifierQuoteChar: [:0]const u8,
    IndexKeywords: IndexKeywords.Result,
    InfoSchemaViews: InfoSchemaViews.Result,
    InsertStatement: InsertStatement.Result,
    Integrity: bool,
    KeysetCursorAttributes1: CursorAttributes1.Result,
    KeysetCursorAttributes2: CursorAttributes2.Result,
    Keywords: [:0]const u8,
    LikeEscapeClause: bool,
    MaxAsyncConcurrentStatements: u32,
    MaxBinaryLiteralLength: u32,
    MaxCatalogNameLength: c_ushort,
    MaxCharLiteralLength: u32,
    MaxColumnNameLength: c_ushort,
    MaxColumnsInGroupBy: c_ushort,
    MaxColumnsInIndex: c_ushort,
    MaxColumnsInOrderBy: c_ushort,
    MaxColumnsInSelect: c_ushort,
    MaxColumnsInTable: c_ushort,
    MaxConcurrentActivities: c_ushort,
    MaxCursorNameLength: c_ushort,
    MaxDriverConnections: c_ushort,
    MaxIdentifierLength: c_ushort,
    MaxIndexSize: u32,
    MaxProcedureNameLength: c_ushort,
    MaxRowSize: u32,
    MaxRowSizeIncludesLong: bool,
    MaxSchemaNameLength: c_ushort,
    MaxStatementLength: u32,
    MaxTableNameLength: c_ushort,
    MaxTablesInSelect: c_ushort,
    MaxUserNameLength: c_ushort,
    MultipleResultSets: bool,
    MultipleActiveTransactions: bool,
    NeedLongDataLength: bool,
    NonNullableColumns: bool,
    NullCollation: NullCollation,
    NumericFunctions: NumericFunctions.Result,
    OdbcInterfaceConformance: InterfaceConformance,
    OdbcVersion: [:0]const u8,
    OJCapabilities: OJCapabilities.Result,
    OrderByColumnsInSelect: bool,
    ParamArrayRowCounts: bool,
    ParamArraySelects: ParamArraySelects.Result,
    PosOperations: PositionOperations.Result,
    ProcedureTerm: [:0]const u8,
    Procedures: bool,
    QuotedIdentifierCase: QuotedIdentifierCase,
    RowUpdates: bool,
    SchemaTerm: [:0]const u8,
    SchemaUsage: SchemaUsage.Result,
    ScrollOptions: ScrollOptions.Result,
    SearchPatternEscape: [:0]const u8,
    ServerName: [:0]const u8,
    SpecialCharacters: [:0]const u8,
    SQLConformance: SQLConformance,
    // OdbcStandardCliConformance: OdbcStandardCliConformance.Result,
    StaticCursorAttributes1: CursorAttributes1.Result,
    StaticCursorAttributes2: CursorAttributes2.Result,
    StringFunctions: StringFunctions.Result,
    SQLSubqueries: Subqueries.Result,
    SystemFunctions: SystemFunctions.Result,
    TableTerm: [:0]const u8,
    TimeDateAddIntervals: TimedateIntervals.Result,
    TimeDateDiffIntervals: TimedateIntervals.Result,
    TimeDateFunctions: TimedateFunctions.Result,
    TransactionCapable: TransactionCapable.Result,
    TransactionIsolationOption: TransactionIsolationOptions.Result,
    Union: Union.Result,
    Username: [:0]const u8,
    XOpenCliYear: [:0]const u8,

    /// Return `true` if the payload type of the active union member is a zig string (slice of u8), `false` otherwise.
    pub fn isStringType(info_value: InformationTypeValue) bool {
        const active_tag = std.meta.activeTag(info_value);
        const itv_info = @typeInfo(InformationTypeValue);
        inline for (itv_info.Union.fields) |field| {
            if (std.mem.eql(u8, field.name, @tagName(active_tag))) {
                if (comptime std.meta.trait.isSlice(field.field_type)) {
                    return @typeInfo(field.field_type).Pointer.child == u8;
                }
                return false;
            }
        }

        unreachable;
    }

    pub const AggregateFunctions = Bitmask(u32, .{
        .{ "all", odbc.SQL_AF_ALL },
        .{ "avg", odbc.SQL_AF_AVG },
        .{ "count", odbc.SQL_AF_COUNT },
        .{ "distinct", odbc.SQL_AF_DISTINCT },
        .{ "max", odbc.SQL_AF_MAX },
        .{ "min", odbc.SQL_AF_MIN },
        .{ "sum", odbc.SQL_AF_SUM },
    });

    pub const AlterDomain = Bitmask(u32, .{
        .{ "add_domain_constraint", odbc.SQL_AD_ADD_DOMAIN_CONSTRAINT },
        .{ "add_domain_default", odbc.SQL_AD_ADD_DOMAIN_DEFAULT },
        .{ "constraint_name_definition", odbc.SQL_AD_CONSTRAINT_NAME_DEFINITION },
        .{ "drop_domain_constraint", odbc.SQL_AD_DROP_DOMAIN_CONSTRAINT },
        .{ "add_constraint_deferrable", odbc.SQL_AD_ADD_CONSTRAINT_DEFERRABLE },
        .{ "add_constraint_non_deferrable", odbc.SQL_AD_ADD_CONSTRAINT_NON_DEFERRABLE },
        .{ "add_constraint_initially_deferred", odbc.SQL_AD_ADD_CONSTRAINT_INITIALLY_DEFERRED },
        .{ "add_constraint_initially_immediate", odbc.SQL_AD_ADD_CONSTRAINT_INITIALLY_IMMEDIATE }
    });

    pub const AlterTable = Bitmask(u32, .{
        .{ "add_column_collation", odbc.SQL_AT_ADD_COLUMN_COLLATION },
        .{ "add_column_default", odbc.SQL_AT_ADD_COLUMN_DEFAULT },
        .{ "add_column_single", odbc.SQL_AT_ADD_COLUMN_SINGLE },
        .{ "add_constraint", odbc.SQL_AT_ADD_CONSTRAINT },
        .{ "add_table_constraint", odbc.SQL_AT_ADD_TABLE_CONSTRAINT },
        .{ "constraint_name_definition", odbc.SQL_AT_CONSTRAINT_NAME_DEFINITION },
        .{ "drop_column_cascade", odbc.SQL_AT_DROP_COLUMN_CASCADE },
        .{ "drop_column_default", odbc.SQL_AT_DROP_COLUMN_DEFAULT },
        .{ "drop_column_restrict", odbc.SQL_AT_DROP_COLUMN_RESTRICT },
        .{ "drop_table_constraint_cascade", odbc.SQL_AT_DROP_TABLE_CONSTRAINT_CASCADE },
        .{ "drop_table_constraint_restrict", odbc.SQL_AT_DROP_TABLE_CONSTRAINT_RESTRICT },
        .{ "set_column_default", odbc.SQL_AT_SET_COLUMN_DEFAULT },
    });

    pub const AsyncMode = enum(u32) {
        Connection = odbc.SQL_AM_CONNECTION,
        Statement = odbc.SQL_AM_STATEMENT,
        None = odbc.SQL_AM_NONE
    };

    pub const BatchRowCount = Bitmask(u32, .{
        .{ "rolled_up", odbc.SQL_BRC_ROLLED_UP },
        .{ "procedures", odbc.SQL_BRC_PROCEDURES },
        .{ "explicit", odbc.SQL_BRC_EXPLICIT }
    });

    pub const BatchSupport = Bitmask(u32, .{
        .{ "select_explicit", odbc.SQL_BS_SELECT_EXPLICIT },
        .{ "row_count_explicit", odbc.SQL_BS_ROW_COUNT_EXPLICIT },
        .{ "select_proc", odbc.SQL_BS_SELECT_PROC },
        .{ "row_count_proc", odbc.SQL_BS_ROW_COUNT_PROC },
    });

    pub const BookmarkPersistence = Bitmask(u32, .{
        .{ "close", odbc.SQL_BP_CLOSE },
        .{ "delete", odbc.SQL_BP_DELETE },
        .{ "drop", odbc.SQL_BP_DROP },
        .{ "transaction", odbc.SQL_BP_TRANSACTION },
        .{ "update", odbc.SQL_BP_UPDATE },
        .{ "other_statement", odbc.SQL_BP_OTHER_HSTMT }
    });

    pub const CatalogLocation = enum(c_ushort) {
        Start = odbc.SQL_CL_START,
        End = odbc.SQL_CL_END
    };

    pub const CatalogUsage = Bitmask(u32, .{
        .{ "dml_statements", odbc.SQL_CU_DML_STATEMENTS },
        .{ "table_definition", odbc.SQL_CU_TABLE_DEFINITION },
        .{ "index_definition", odbc.SQL_CU_INDEX_DEFINITION },
        .{ "privilege_definition", odbc.SQL_CU_PRIVILEGE_DEFINITION }
    });

    pub const ConcatNullBehavior = enum(c_ushort) {
        Null = odbc.SQL_CB_NULL,
        NonNull = odbc.SQL_CB_NON_NULL
    };

    pub const SupportedConversion = Bitmask(u32, .{
        .{ "bigint", odbc.SQL_CVT_BIGINT },
        .{ "binary", odbc.SQL_CVT_BINARY },
        .{ "bit", odbc.SQL_CVT_BIT },
        .{ "guid", odbc.SQL_CVT_BIT },
        .{ "char", odbc.SQL_CVT_CHAR },
        .{ "date", odbc.SQL_CVT_CHAR },
        .{ "decimal", odbc.SQL_CVT_DECIMAL },
        .{ "double", odbc.SQL_CVT_DOUBLE },
        .{ "float", odbc.SQL_CVT_FLOAT },
        .{ "integer", odbc.SQL_CVT_INTEGER },
        .{ "interval_year_month", odbc.SQL_CVT_INTERVAL_YEAR_MONTH },
        .{ "interval_day_time", odbc.SQL_CVT_INTERVAL_DAY_TIME },
        .{ "long_var_binary", odbc.SQL_CVT_LONGVARBINARY },
        .{ "long_var_char", odbc.SQL_CVT_LONGVARCHAR },
        .{ "numeric", odbc.SQL_CVT_NUMERIC },
        .{ "real", odbc.SQL_CVT_REAL },
        .{ "small_int", odbc.SQL_CVT_SMALLINT },
        .{ "time", odbc.SQL_CVT_TIME },
        .{ "timestamp", odbc.SQL_CVT_TIMESTAMP },
        .{ "tiny_int", odbc.SQL_CVT_TINYINT },
        .{ "var_binary", odbc.SQL_CVT_VARBINARY },
        .{ "var_char", odbc.SQL_CVT_VARCHAR }
    });

    pub const ConvertFunctions = Bitmask(u32, .{
        .{ "cast", odbc.SQL_FN_CVT_CAST },
        .{ "convert", odbc.SQL_FN_CVT_CONVERT }
    });

    pub const CorrelationName = enum(c_ushort) {
        None = odbc.SQL_CN_NONE,
        Different = odbc.SQL_CN_DIFFERENT,
        Any = odbc.SQL_CN_ANY
    };

    pub const CreateAssertion = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CA_CREATE_ASSERTION },
        .{ "constraint_initially_deferred", odbc.SQL_CA_CONSTRAINT_INITIALLY_DEFERRED },
        .{ "constraint_initially_immediate", odbc.SQL_CA_CONSTRAINT_INITIALLY_IMMEDIATE },
        .{ "constraint_deferrable", odbc.SQL_CA_CONSTRAINT_DEFERRABLE },
        .{ "constraint_non_deferrable", odbc.SQL_CA_CONSTRAINT_NON_DEFERRABLE }
    });

    pub const CreateCharacterSet = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CCS_CREATE_CHARACTER_SET },
        .{ "collate_clause", odbc.SQL_CCS_COLLATE_CLAUSE },
        .{ "limited_collation", odbc.SQL_CCS_LIMITED_COLLATION }
    });

    pub const CreateCollation = Bitmask(u32, .{ .{ "supported", odbc.SQL_CCOL_CREATE_COLLATION }});

    pub const CreateDomain = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CDO_CREATE_DOMAIN },
        .{ "supports_defaults", odbc.SQL_CDO_DEFAULT },
        .{ "supports_constraints", odbc.SQL_CDO_CONSTRAINT },
        .{ "supports_collation", odbc.SQL_CDO_COLLATION },
        .{ "constraint_initially_deferred", odbc.SQL_CDO_CONSTRAINT_INITIALLY_DEFERRED },
        .{ "constraint_initially_immediate", odbc.SQL_CDO_CONSTRAINT_INITIALLY_IMMEDIATE },
        .{ "constraint_deferrable", odbc.SQL_CDO_CONSTRAINT_DEFERRABLE },
        .{ "constraint_non_deferrable", odbc.SQL_CDO_CONSTRAINT_NON_DEFERRABLE }
    });

    pub const CreateSchema = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CS_CREATE_SCHEMA },
        .{ "authorization", odbc.SQL_CS_AUTHORIZATION },
        .{ "default_character_set", odbc.SQL_CS_DEFAULT_CHARACTER_SET }
    });

    pub const CreateTable = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CT_CREATE_TABLE },
        .{ "table_constraints", odbc.SQL_CT_TABLE_CONSTRAINT },
        .{ "constraint_name_definition", odbc.SQL_CT_CONSTRAINT_NAME_DEFINITION },
        .{ "commit_preserve", odbc.SQL_CT_COMMIT_PRESERVE },
        .{ "commit_delete", odbc.SQL_CT_COMMIT_DELETE },
        .{ "global_temporary", odbc.SQL_CT_GLOBAL_TEMPORARY },
        .{ "local_temporary", odbc.SQL_CT_LOCAL_TEMPORARY },
        .{ "column_constraint_supported", odbc.SQL_CT_COLUMN_CONSTRAINT },
        .{ "column_default", odbc.SQL_CT_COLUMN_DEFAULT },
        .{ "column_collation", odbc.SQL_CT_COLUMN_COLLATION },
        .{ "constraint_initially_deferred", odbc.SQL_CT_CONSTRAINT_INITIALLY_DEFERRED },
        .{ "constraint_initially_immediate", odbc.SQL_CT_CONSTRAINT_INITIALLY_IMMEDIATE },
        .{ "constraint_deferrable", odbc.SQL_CT_CONSTRAINT_DEFERRABLE },
        .{ "constraint_non_deferrable", odbc.SQL_CT_CONSTRAINT_NON_DEFERRABLE }
    });

    pub const CreateTranslation = Bitmask(u32, .{ .{ "supported", odbc.SQL_CTR_CREATE_TRANSLATION }});

    pub const CreateView = Bitmask(u32, .{
        .{ "supported", odbc.SQL_CV_CREATE_VIEW },
        .{ "check_option", odbc.SQL_CV_CHECK_OPTION },
        .{ "cascaded", odbc.SQL_CV_CASCADED },
        .{ "local", odbc.SQL_CV_LOCAL }
    });

    pub const CursorCommitBehavior = enum(c_ushort) {
        Delete = odbc.SQL_CB_DELETE,
        Close = odbc.SQL_CB_CLOSE,
        Preserve = odbc.SQL_CB_PRESERVE
    };

    pub const CursorRollbackBehavior = enum(c_ushort) {
        Delete = odbc.SQL_CB_DELETE,
        Close = odbc.SQL_CB_CLOSE,
        Preserve = odbc.SQL_CB_PRESERVE
    };

    pub const CursorSensitivity = enum(u32) {
        Insensitive = odbc.SQL_INSENSITIVE,
        Unspecified = odbc.SQL_UNSPECIFIED,
        Sensitive = odbc.SQL_SENSITIVE
    };

    pub const DatetimeLiterals = Bitmask(u32, .{
        .{ "date", odbc.SQL_DL_SQL92_DATE },
        .{ "time", odbc.SQL_DL_SQL92_TIME },
        .{ "timestamp", odbc.SQL_DL_SQL92_TIMESTAMP },
        .{ "interval_year", odbc.SQL_DL_SQL92_INTERVAL_YEAR },
        .{ "interval_month", odbc.SQL_DL_SQL92_INTERVAL_MONTH },
        .{ "interval_day", odbc.SQL_DL_SQL92_INTERVAL_DAY },
        .{ "interval_hour", odbc.SQL_DL_SQL92_INTERVAL_HOUR },
        .{ "interval_minute", odbc.SQL_DL_SQL92_INTERVAL_MINUTE },
        .{ "interval_second", odbc.SQL_DL_SQL92_INTERVAL_SECOND },
        .{ "interval_year_to_month", odbc.SQL_DL_SQL92_INTERVAL_YEAR_TO_MONTH },
        .{ "interval_day_to_hour", odbc.SQL_DL_SQL92_INTERVAL_DAY_TO_HOUR },
        .{ "interval_day_to_minute", odbc.SQL_DL_SQL92_INTERVAL_DAY_TO_MINUTE },
        .{ "interval_day_to_second", odbc.SQL_DL_SQL92_INTERVAL_DAY_TO_SECOND },
        .{ "interval_hour_to_minute", odbc.SQL_DL_SQL92_INTERVAL_HOUR_TO_MINUTE },
        .{ "interval_hour_to_second", odbc.SQL_DL_SQL92_INTERVAL_HOUR_TO_SECOND },
        .{ "interval_minute_to_second", odbc.SQL_DL_SQL92_INTERVAL_MINUTE_TO_SECOND },
    });

    pub const DDLIndex = Bitmask(u32, .{
        .{ "create_index", odbc.SQL_DI_CREATE_INDEX },
        .{ "drop_index", odbc.SQL_DI_DROP_INDEX }
    });

    pub const DefaultTransactionIsolation = Bitmask(u32, .{
        .{ "read_uncommitted", odbc.SQL_TXN_READ_UNCOMMITTED },
        .{ "read_committed", odbc.SQL_TXN_READ_COMMITTED },
        .{ "repeatable_read", odbc.SQL_TXN_REPEATABLE_READ },
        .{ "serializable", odbc.SQL_TXN_SERIALIZABLE }
    });

    pub const DropAssertion = Bitmask(u32, .{ .{ "supported", odbc.SQL_DA_DROP_ASSERTION }});

    pub const DropCharacterSet = Bitmask(u32, .{ .{ "supported", odbc.SQL_DCS_DROP_CHARACTER_SET }});

    pub const DropCollation = Bitmask(u32, .{ .{ "supported", odbc.SQL_DC_DROP_COLLATION }});

    pub const DropDomain = Bitmask(u32, .{
        .{ "supported", odbc.SQL_DD_DROP_DOMAIN },
        .{ "cascade", odbc.SQL_DD_CASCADE },
        .{ "restrict", odbc.SQL_DD_RESTRICT }
    });

    pub const DropSchema = Bitmask(u32, .{
        .{ "supported", odbc.SQL_DS_DROP_SCHEMA },
        .{ "cascade", odbc.SQL_DS_CASCADE },
        .{ "restrict", odbc.SQL_DS_RESTRICT }
    });

    pub const DropTable = Bitmask(u32, .{
        .{ "supported", odbc.SQL_DT_DROP_TABLE },
        .{ "cascade", odbc.SQL_DT_CASCADE },
        .{ "restrict", odbc.SQL_DT_RESTRICT }
    });

    pub const DropTranslation = Bitmask(u32, .{ .{ "supported", odbc.SQL_DTR_DROP_TRANSLATION }});

    pub const DropView = Bitmask(u32, .{
        .{ "supported", odbc.SQL_DV_DROP_VIEW },
        .{ "cascade", odbc.SQL_DV_CASCADE },
        .{ "restrict", odbc.SQL_DV_RESTRICT }
    });
    
    pub const CursorAttributes1 = Bitmask(u32, .{
        .{ "next", odbc.SQL_CA1_NEXT },
        .{ "absolute", odbc.SQL_CA1_ABSOLUTE },
        .{ "relative", odbc.SQL_CA1_RELATIVE },
        .{ "bookmark", odbc.SQL_CA1_BOOKMARK },
        .{ "lock_exclusive", odbc.SQL_CA1_LOCK_EXCLUSIVE },
        .{ "lock_no_change", odbc.SQL_CA1_LOCK_NO_CHANGE },
        .{ "lock_unlock", odbc.SQL_CA1_LOCK_UNLOCK },
        .{ "position", odbc.SQL_CA1_POS_POSITION },
        .{ "position_update", odbc.SQL_CA1_POS_UPDATE },
        .{ "position_delete", odbc.SQL_CA1_POS_DELETE },
        .{ "position_refresh", odbc.SQL_CA1_POS_REFRESH },
        .{ "positioned_update", odbc.SQL_CA1_POSITIONED_UPDATE },
        .{ "positioned_delete", odbc.SQL_CA1_POSITIONED_DELETE },
        .{ "select_for_update", odbc.SQL_CA1_SELECT_FOR_UPDATE },
        .{ "bulk_add", odbc.SQL_CA1_BULK_ADD },
        .{ "bulk_update_by_bookmark", odbc.SQL_CA1_BULK_UPDATE_BY_BOOKMARK },
        .{ "bulk_delete_by_bookmark", odbc.SQL_CA1_BULK_DELETE_BY_BOOKMARK },
        .{ "bulk_fetch_by_bookmark", odbc.SQL_CA1_BULK_FETCH_BY_BOOKMARK },
    });

    pub const CursorAttributes2 = Bitmask(u32, .{
        .{ "read_only_concurrency", odbc.SQL_CA2_READ_ONLY_CONCURRENCY },
        .{ "lock_concurrency", odbc.SQL_CA2_LOCK_CONCURRENCY },
        .{ "optimistic_row_version_concurrency", odbc.SQL_CA2_OPT_ROWVER_CONCURRENCY },
        .{ "optimistic_values_concurrency", odbc.SQL_CA2_OPT_VALUES_CONCURRENCY },
        .{ "sensitivity_additions", odbc.SQL_CA2_SENSITIVITY_ADDITIONS },
        .{ "sensitivity_deletions", odbc.SQL_CA2_SENSITIVITY_DELETIONS },
        .{ "sensitivity_updates", odbc.SQL_CA2_SENSITIVITY_UPDATES },
        .{ "max_rows_select", odbc.SQL_CA2_MAX_ROWS_SELECT },
        .{ "max_rows_insert", odbc.SQL_CA2_MAX_ROWS_INSERT },
        .{ "max_rows_delete", odbc.SQL_CA2_MAX_ROWS_DELETE },
        .{ "max_rows_update", odbc.SQL_CA2_MAX_ROWS_UPDATE },
        .{ "max_rows_catalog", odbc.SQL_CA2_MAX_ROWS_CATALOG },
        .{ "max_rows_affects_all", odbc.SQL_CA2_MAX_ROWS_AFFECTS_ALL },
        .{ "exact_cursor_row_count", odbc.SQL_CA2_CRC_EXACT },
        .{ "approximate_cursor_row_count", odbc.SQL_CA2_CRC_APPROXIMATE },
        .{ "simulate_non_unique", odbc.SQL_CA2_SIMULATE_NON_UNIQUE },
        .{ "simulate_try_unique", odbc.SQL_CA2_SIMULATE_TRY_UNIQUE },
        .{ "simulate_unique", odbc.SQL_CA2_SIMULATE_UNIQUE },
    });

    pub const FileUsage = enum(c_ushort) {
        NotSupported = odbc.SQL_FILE_NOT_SUPPORTED,
        Table = odbc.SQL_FILE_TABLE,
        Catalog = odbc.SQL_FILE_CATALOG
    };

    pub const GetDataExtensions = Bitmask(u32, .{
        .{ "any_column", odbc.SQL_GD_ANY_COLUMN },
        .{ "any_order", odbc.SQL_GD_ANY_ORDER },
        .{ "block", odbc.SQL_GD_BLOCK },
        .{ "bound", odbc.SQL_GD_BOUND },
        .{ "output_params", odbc.SQL_GD_OUTPUT_PARAMS }
    });

    pub const GroupBy = enum(c_ushort) {
        Collate = odbc.SQL_GB_COLLATE,
        NotSupported = odbc.SQL_GB_NOT_SUPPORTED,
        GroupByEqualsSelect = odbc.SQL_GB_GROUP_BY_EQUALS_SELECT,
        NoRelation = odbc.SQL_GB_NO_RELATION
    };

    pub const IdentifierCase = enum(c_ushort) {
        Upper = odbc.SQL_IC_UPPER,
        Lower = odbc.SQL_IC_LOWER,
        Sensitive = odbc.SQL_IC_SENSITIVE,
        Mixed = odbc.SQL_IC_MIXED
    };

    pub const IndexKeywords = Bitmask(u32, .{
        .{ "none", odbc.SQL_IK_NONE },
        .{ "asc", odbc.SQL_IK_ASC },
        .{ "desc", odbc.SQL_IK_DESC },
        .{ "all", odbc.SQL_IK_ALL }
    });

    pub const InfoSchemaViews = Bitmask(u32, .{
        .{ "assertions", odbc.SQL_ISV_ASSERTIONS },
        .{ "character_sets", odbc.SQL_ISV_CHARACTER_SETS },
        .{ "check_constraints", odbc.SQL_ISV_CHECK_CONSTRAINTS },
        .{ "collations", odbc.SQL_ISV_COLLATIONS },
        .{ "column_domain_usage", odbc.SQL_ISV_COLUMN_DOMAIN_USAGE },
        .{ "column_privileges", odbc.SQL_ISV_COLUMN_PRIVILEGES },
        .{ "columns", odbc.SQL_ISV_COLUMNS },
        .{ "constraint_column_usage", odbc.SQL_ISV_CONSTRAINT_COLUMN_USAGE },
        .{ "constraint_table_usage", odbc.SQL_ISV_CONSTRAINT_TABLE_USAGE },
        .{ "domain_constraints", odbc.SQL_ISV_DOMAIN_CONSTRAINTS },
        .{ "domains", odbc.SQL_ISV_DOMAINS },
        .{ "key_column_usage", odbc.SQL_ISV_KEY_COLUMN_USAGE },
        .{ "referential_constraints", odbc.SQL_ISV_REFERENTIAL_CONSTRAINTS },
        .{ "schemata", odbc.SQL_ISV_SCHEMATA },
        .{ "sql_languages", odbc.SQL_ISV_SQL_LANGUAGES },
        .{ "table_constraints", odbc.SQL_ISV_TABLE_CONSTRAINTS },
        .{ "table_privileges", odbc.SQL_ISV_TABLE_PRIVILEGES },
        .{ "tables", odbc.SQL_ISV_TABLES },
        .{ "translations", odbc.SQL_ISV_TRANSLATIONS },
        .{ "usage_privileges", odbc.SQL_ISV_USAGE_PRIVILEGES },
        .{ "view_column_usage", odbc.SQL_ISV_VIEW_COLUMN_USAGE },
        .{ "view_table_usage", odbc.SQL_ISV_VIEW_TABLE_USAGE },
        .{ "views", odbc.SQL_ISV_VIEWS }
    });

    pub const InsertStatement = Bitmask(u32, .{
        .{ "insert_literals", odbc.SQL_IS_INSERT_LITERALS },
        .{ "insert_searched", odbc.SQL_IS_INSERT_SEARCHED },
        .{ "select_into", odbc.SQL_IS_SELECT_INTO },
    });

    pub const NullCollation = enum(c_ushort) {
        End = odbc.SQL_NC_END,
        High = odbc.SQL_NC_HIGH,
        Low = odbc.SQL_NC_LOW,
        Start = odbc.SQL_NC_START
    };

    pub const NumericFunctions = Bitmask(u32, .{
        .{ "abs", odbc.SQL_FN_NUM_ABS },
        .{ "acos", odbc.SQL_FN_NUM_ACOS },
        .{ "asin", odbc.SQL_FN_NUM_ASIN },
        .{ "atan", odbc.SQL_FN_NUM_ATAN },
        .{ "atan2", odbc.SQL_FN_NUM_ATAN2 },
        .{ "ceiling", odbc.SQL_FN_NUM_CEILING },
        .{ "cos", odbc.SQL_FN_NUM_COS },
        .{ "cot", odbc.SQL_FN_NUM_COT },
        .{ "degrees", odbc.SQL_FN_NUM_DEGREES },
        .{ "exp", odbc.SQL_FN_NUM_EXP },
        .{ "floor", odbc.SQL_FN_NUM_FLOOR },
        .{ "log", odbc.SQL_FN_NUM_LOG },
        .{ "log10", odbc.SQL_FN_NUM_LOG10 },
        .{ "mod", odbc.SQL_FN_NUM_MOD },
        .{ "pi", odbc.SQL_FN_NUM_PI },
        .{ "power", odbc.SQL_FN_NUM_POWER },
        .{ "radians", odbc.SQL_FN_NUM_RADIANS },
        .{ "rand", odbc.SQL_FN_NUM_RAND },
        .{ "round", odbc.SQL_FN_NUM_ROUND },
        .{ "sign", odbc.SQL_FN_NUM_SIGN },
        .{ "sin", odbc.SQL_FN_NUM_SIN },
        .{ "sqrt", odbc.SQL_FN_NUM_SQRT },
        .{ "tan", odbc.SQL_FN_NUM_TAN },
        .{ "truncate", odbc.SQL_FN_NUM_TRUNCATE },
    });

    pub const InterfaceConformance = enum(u32) {
        Core = odbc.SQL_OIC_CORE,
        Level1 = odbc.SQL_OIC_LEVEL1,
        Level2 = odbc.SQL_OIC_LEVEL2
    };

    pub const OJCapabilities = Bitmask(u32, .{
        .{ "left", odbc.SQL_OJ_LEFT },
        .{ "right", odbc.SQL_OJ_RIGHT },
        .{ "full", odbc.SQL_OJ_FULL },
        .{ "nested", odbc.SQL_OJ_NESTED },
        .{ "not_ordered", odbc.SQL_OJ_NOT_ORDERED },
        .{ "inner", odbc.SQL_OJ_INNER },
        .{ "all_comparison_op", odbc.SQL_OJ_ALL_COMPARISON_OPS },
    });

    pub const ParamArraySelects = Bitmask(u32, .{
        .{ "batch", odbc.SQL_PAS_BATCH },
        .{ "no_batch", odbc.SQL_PAS_NO_BATCH },
        .{ "no_select", odbc.SQL_PAS_NO_SELECT },
    });

    pub const PositionOperations = Bitmask(u32, .{
        .{ "supported", odbc.SQL_POS_POSITION },
        .{ "refresh", odbc.SQL_POS_REFRESH },
        .{ "update", odbc.SQL_POS_UPDATE },
        .{ "delete", odbc.SQL_POS_DELETE },
        .{ "add", odbc.SQL_POS_ADD },
    });

    pub const QuotedIdentifierCase = enum(c_ushort) {
        Upper = odbc.SQL_IC_UPPER,
        Lower = odbc.SQL_IC_LOWER,
        Sensitive = odbc.SQL_IC_SENSITIVE,
        Mixed = odbc.SQL_IC_MIXED
    };

    pub const SchemaUsage = Bitmask(u32, .{
        .{ "dml_statements", odbc.SQL_SU_DML_STATEMENTS },
        .{ "procedure_invocation", odbc.SQL_SU_PROCEDURE_INVOCATION },
        .{ "table_definition", odbc.SQL_SU_TABLE_DEFINITION },
        .{ "index_definition", odbc.SQL_SU_INDEX_DEFINITION },
        .{ "privilege_definition", odbc.SQL_SU_PRIVILEGE_DEFINITION },
    });

    pub const ScrollOptions = Bitmask(u32, .{
        .{ "forward_only", odbc.SQL_SO_FORWARD_ONLY },
        .{ "static", odbc.SQL_SO_STATIC },
        .{ "keyset_driven", odbc.SQL_SO_KEYSET_DRIVEN },
        .{ "dynamic", odbc.SQL_SO_DYNAMIC },
        .{ "mixed", odbc.SQL_SO_MIXED },
    });

    pub const SQLConformance = enum(u32) {
        SQL92Entry = odbc.SQL_SC_SQL92_ENTRY,
        FIPS127_2 = odbc.SQL_SC_FIPS127_2_TRANSITIONAL,
        SQL92Full = odbc.SQL_SC_SQL92_FULL,
        SQL92Intermediate = odbc.SQL_SC_SQL92_INTERMEDIATE,
    };

    pub const DatetimeFunctions = Bitmask(u32, .{
        .{ "current_date", odbc.SQL_SDF_CURRENT_DATE },
        .{ "current_time", odbc.SQL_SDF_CURRENT_TIME },
        .{ "current_timestamp", odbc.SQL_SDF_CURRENT_TIMESTAMP },
    });

    pub const OdbcStandardCliConformance = Bitmask(u32, .{
        .{ "xopen_cli_version1", odbc.SQL_SCC_XOPEN_CLI_VERSION1 },
        .{ "iso92_cli", odbc.SQL_SCC_ISO92_CLI },
    });

    pub const StringFunctions = Bitmask(u32, .{
        .{ "ascii", odbc.SQL_FN_STR_ASCII },
        .{ "bit_length", odbc.SQL_FN_STR_BIT_LENGTH },
        .{ "char", odbc.SQL_FN_STR_CHAR },
        .{ "char_length", odbc.SQL_FN_STR_CHAR_LENGTH },
        .{ "character_length", odbc.SQL_FN_STR_CHARACTER_LENGTH },
        .{ "concat", odbc.SQL_FN_STR_CONCAT },
        .{ "difference", odbc.SQL_FN_STR_DIFFERENCE },
        .{ "insert", odbc.SQL_FN_STR_INSERT },
        .{ "lcase", odbc.SQL_FN_STR_LCASE },
        .{ "left", odbc.SQL_FN_STR_LEFT },
        .{ "length", odbc.SQL_FN_STR_LENGTH },
        .{ "locate", odbc.SQL_FN_STR_LOCATE },
        .{ "ltrim", odbc.SQL_FN_STR_LTRIM },
        .{ "octet_length", odbc.SQL_FN_STR_OCTET_LENGTH },
        .{ "position", odbc.SQL_FN_STR_POSITION },
        .{ "repeat", odbc.SQL_FN_STR_REPEAT },
        .{ "replace", odbc.SQL_FN_STR_REPLACE },
        .{ "right", odbc.SQL_FN_STR_RIGHT },
        .{ "rtrim", odbc.SQL_FN_STR_RTRIM },
        .{ "soundex", odbc.SQL_FN_STR_SOUNDEX },
        .{ "space", odbc.SQL_FN_STR_SPACE },
        .{ "substring", odbc.SQL_FN_STR_SUBSTRING },
        .{ "ucase", odbc.SQL_FN_STR_UCASE },
    });

    pub const Subqueries = Bitmask(u32, .{
        .{ "correlated_subqueries", odbc.SQL_SQ_CORRELATED_SUBQUERIES },
        .{ "comparison", odbc.SQL_SQ_COMPARISON },
        .{ "exists", odbc.SQL_SQ_EXISTS },
    });

    pub const SystemFunctions = Bitmask(u32, .{
        .{ "db_name", odbc.SQL_FN_SYS_DBNAME },
        .{ "if_null", odbc.SQL_FN_SYS_IFNULL },
        .{ "username", odbc.SQL_FN_SYS_USERNAME },
    });

    pub const TimedateIntervals = Bitmask(u32, .{
        .{ "frac_second", odbc.SQL_FN_TSI_FRAC_SECOND },
        .{ "second", odbc.SQL_FN_TSI_SECOND },
        .{ "minute", odbc.SQL_FN_TSI_MINUTE },
        .{ "hour", odbc.SQL_FN_TSI_HOUR },
        .{ "day", odbc.SQL_FN_TSI_DAY },
        .{ "week", odbc.SQL_FN_TSI_WEEK },
        .{ "month", odbc.SQL_FN_TSI_MONTH },
        .{ "quarter", odbc.SQL_FN_TSI_QUARTER },
        .{ "year", odbc.SQL_FN_TSI_YEAR },
    });

    pub const TimedateFunctions = Bitmask(u32, .{
        .{ "current_date", odbc.SQL_FN_TD_CURRENT_DATE },
        .{ "current_time", odbc.SQL_FN_TD_CURRENT_TIME },
        .{ "current_timestamp", odbc.SQL_FN_TD_CURRENT_TIMESTAMP },
        .{ "curdate", odbc.SQL_FN_TD_CURDATE },
        .{ "curtime", odbc.SQL_FN_TD_CURTIME },
        .{ "day_name", odbc.SQL_FN_TD_DAYNAME },
        .{ "day_of_month", odbc.SQL_FN_TD_DAYOFMONTH },
        .{ "day_of_week", odbc.SQL_FN_TD_DAYOFWEEK },
        .{ "day_of_year", odbc.SQL_FN_TD_DAYOFYEAR },
        .{ "extract", odbc.SQL_FN_TD_EXTRACT },
        .{ "hour", odbc.SQL_FN_TD_HOUR },
        .{ "minute", odbc.SQL_FN_TD_MINUTE },
        .{ "month", odbc.SQL_FN_TD_MONTH },
        .{ "month_name", odbc.SQL_FN_TD_MONTHNAME },
        .{ "now", odbc.SQL_FN_TD_NOW },
        .{ "quarter", odbc.SQL_FN_TD_QUARTER },
        .{ "second", odbc.SQL_FN_TD_SECOND },
        .{ "timestamp_add", odbc.SQL_FN_TD_TIMESTAMPADD },
        .{ "timestamp_diff", odbc.SQL_FN_TD_TIMESTAMPDIFF },
        .{ "week", odbc.SQL_FN_TD_WEEK },
        .{ "year", odbc.SQL_FN_TD_YEAR },
    });

    pub const TransactionCapable = Bitmask(u32, .{
        .{ "none", odbc.SQL_TC_NONE },
        .{ "dml", odbc.SQL_TC_DML },
        .{ "ddl_commit", odbc.SQL_TC_DDL_COMMIT },
        .{ "ddl_ignore", odbc.SQL_TC_DDL_IGNORE },
        .{ "all", odbc.SQL_TC_ALL },
    });

    pub const TransactionIsolationOptions = Bitmask(u32, .{
        .{ "read_uncommitted", odbc.SQL_TXN_READ_UNCOMMITTED },
        .{ "read_committed", odbc.SQL_TXN_READ_COMMITTED },
        .{ "repeatable_read", odbc.SQL_TXN_REPEATABLE_READ },
        .{ "serializable", odbc.SQL_TXN_SERIALIZABLE },
    });

    pub const Union = Bitmask(u32, .{
        .{ "union", odbc.SQL_U_UNION },
        .{ "union_all", odbc.SQL_U_UNION_ALL },
    });

};

pub const CType = enum(odbc.SQLSMALLINT) {
    Char = odbc.SQL_C_CHAR,
    WChar = odbc.SQL_C_WCHAR,
    SShort = odbc.SQL_C_SSHORT,
    UShort = odbc.SQL_C_USHORT,
    SLong = odbc.SQL_C_SLONG,
    ULong = odbc.SQL_C_ULONG,
    Float = odbc.SQL_C_FLOAT,
    Double = odbc.SQL_C_DOUBLE,
    Bit = odbc.SQL_C_BIT,
    STinyInt = odbc.SQL_C_STINYINT,
    UTinyInt = odbc.SQL_C_UTINYINT,
    SBigInt = odbc.SQL_C_SBIGINT,
    UBigInt = odbc.SQL_C_UBIGINT, // @note: Use this for Bookmark values
    Binary = odbc.SQL_C_BINARY, // @note: Use this for VarBookmark values
    IntervalMonth = odbc.SQL_INTERVAL_MONTH,
    IntervalYear = odbc.SQL_INTERVAL_YEAR,
    IntervalYearToMonth = odbc.SQL_INTERVAL_YEAR_TO_MONTH,
    IntervalDay = odbc.SQL_INTERVAL_DAY,
    IntervalHour = odbc.SQL_INTERVAL_HOUR,
    IntervalMinute = odbc.SQL_INTERVAL_MINUTE,
    IntervalSecond = odbc.SQL_INTERVAL_SECOND,
    IntervalDayToHour = odbc.SQL_INTERVAL_DAY_TO_HOUR,
    IntervalDayToMinute = odbc.SQL_INTERVAL_DAY_TO_MINUTE,
    IntervalDayToSecond = odbc.SQL_INTERVAL_DAY_TO_SECOND,
    IntervalHourToMinute = odbc.SQL_INTERVAL_HOUR_TO_MINUTE,
    IntervalHourToSecond = odbc.SQL_INTERVAL_HOUR_TO_SECOND,
    IntervalMinuteToSecond = odbc.SQL_INTERVAL_MINUTE_TO_SECOND,
    Date = odbc.SQL_C_TYPE_DATE,
    Time = odbc.SQL_C_TYPE_TIME,
    Timestamp = odbc.SQL_C_TYPE_TIMESTAMP,
    Numeric = odbc.SQL_C_NUMERIC,
    Guid = odbc.SQL_C_GUID,

    pub const Interval = struct {
        pub const IntervalType = enum(odbc.SQLSMALLINT) {
            Year = 1,
            Month = 2,
            Day = 3,
            Hour = 4,
            Minute = 5,
            Seconds = 6,
            YearToMonth = 7,
            DayToHour = 8,
            DayToMinute = 9,
            DayToSecond = 10,
            HourToMinute = 11,
            HourToSecond = 12,
            MinuteToSecond = 13
        };

        pub const YearMonth = packed struct {
            year: u32,
            month: u32
        };

        pub const DaySecond = packed struct {
            day: u32,
            hour: u32,
            minute: u32,
            second: u32,
            fraction: u32
        };

        interval_type: IntervalType,
        // interval_sign: IntervalSign,
        int_val: union(enum) {
            year_month: YearMonth,
            day_second: DaySecond 
        },
    };

    pub const SqlDate = packed struct {
        year: odbc.SQLSMALLINT,
        month: c_ushort,
        day: c_ushort,
    };

    pub const SqlTime = packed struct {
        hour: c_ushort,
        minute: c_ushort,
        second: c_ushort,
    };

    pub const SqlTimestamp = packed struct {
        year: odbc.SQLSMALLINT,
        month: c_ushort,
        day: c_ushort,
        hour: c_ushort,
        minute: c_ushort,
        second: c_ushort,
        fraction: c_ushort,
    };

    pub const SqlNumeric = packed struct {
        precision: odbc.SQLCHAR,
        scale: odbc.SQLSCHAR,
        sign: odbc.SQLCHAR,
        val: [odbc.SQL_MAX_NUMERIC_LEN]odbc.SQLCHAR,
    };

    pub const SqlGuid = packed struct {
        data_1: u32,
        data_2: u16,
        data_3: u16,
        data_4: u8
    };

    pub fn toType(comptime odbc_type: CType) type {
        return switch (odbc_type) {
            .Char => u8,
            .WChar => u16,
            .SShort => c_short,
            .UShort => c_ushort,
            .SLong => c_long,
            .ULong => c_ulong,
            .Float => f32,
            .Double => f64,
            .Bit => u8,
            .STinyInt => i8,
            .UTinyInt => u8,
            .SBigInt => i64,
            .UBigInt => u64,
            .Binary => u8,
            .IntervalMonth, .IntervalYear, .IntervalYearToMonth, .IntervalDay,
            .IntervalHour, .IntervalMinute, .IntervalSecond,
            .IntervalDayToHour, .IntervalDayToMinute, .IntervalDayToSecond,
            .IntervalHourToMinute, .IntervalHourToSecond, .IntervalMinuteToSecond => Interval,
            .Date => SqlDate,
            .Time => SqlTime,
            .Timestamp => SqlTimestamp,
            .Numeric => SqlNumeric,
            .Guid => SqlGuid,
        };
    }

    pub fn fromType(comptime T: type) ?CType {
        if (std.meta.trait.isZigString(T)) return .Char;
        switch (@typeInfo(T)) {
            .Array => {
                if (@typeInfo(T).Array.child == u8) return .Char; 
                if (@typeInfo(T).Array.child == u16) return .WChar; 
            },
            else => {}
        }
        return switch (T) {
            SqlDate => .Date,
            SqlTime => .Time,
            SqlTimestamp => .Timestamp,
            SqlNumeric => .Numeric,
            SqlGuid => .Guid,
            c_short, i16 => .SShort,
            c_ushort, u16 => .UShort,
            c_long, i32 => .SLong,
            c_ulong, u32 => .ULong,
            f32 => .Float,
            f64 => .Double,
            i8 => .STinyInt,
            u8 => .UTinyInt,
            i64, c_longlong => .SBigInt,
            u64, c_ulonglong => .UBigInt,
            else => null
        };
    }

    pub fn isSlice(c_type: CType) bool {
        return switch (c_type) {
            .Char, .WChar, .Binary, => true,
            else => false
        };
    }

    pub fn defaultSqlType(comptime c_type: CType) ?SqlType {
        const zig_type = c_type.toType();
        return SqlType.fromType(zig_type);
    }

};

pub const SqlType = extern enum(odbc.SQLSMALLINT) {
    Char = odbc.SQL_CHAR,
    Varchar = odbc.SQL_VARCHAR,
    LongVarchar = odbc.SQL_LONGVARCHAR,
    WChar = odbc.SQL_WCHAR,
    WVarchar = odbc.SQL_WVARCHAR,
    WLongVarchar = odbc.SQL_WLONGVARCHAR,
    Decimal = odbc.SQL_DECIMAL,
    Numeric = odbc.SQL_NUMERIC,
    SmallInt = odbc.SQL_SMALLINT,
    Integer = odbc.SQL_INTEGER,
    Real = odbc.SQL_REAL,
    Float = odbc.SQL_FLOAT,
    Double = odbc.SQL_DOUBLE,
    Bit = odbc.SQL_BIT,
    TinyInt = odbc.SQL_TINYINT,
    BigInt = odbc.SQL_BIGINT,
    Binary = odbc.SQL_BINARY,
    VarBinary = odbc.SQL_VARBINARY,
    LongVarBinary = odbc.SQL_LONGVARBINARY,
    Date = odbc.SQL_TYPE_DATE,
    Time = odbc.SQL_TYPE_TIME,
    Timestamp = odbc.SQL_TYPE_TIMESTAMP,
    IntervalMonth = odbc.SQL_INTERVAL_MONTH,
    IntervalYear = odbc.SQL_INTERVAL_YEAR,
    IntervalYearToMonth = odbc.SQL_INTERVAL_YEAR_TO_MONTH,
    IntervalDay = odbc.SQL_INTERVAL_DAY,
    IntervalHour = odbc.SQL_INTERVAL_HOUR,
    IntervalMinute = odbc.SQL_INTERVAL_MINUTE,
    IntervalSecond = odbc.SQL_INTERVAL_SECOND,
    IntervalDayToHour = odbc.SQL_INTERVAL_DAY_TO_HOUR,
    IntervalDayToMinute = odbc.SQL_INTERVAL_DAY_TO_MINUTE,
    IntervalDayToSecond = odbc.SQL_INTERVAL_DAY_TO_SECOND,
    IntervalHourToMinute = odbc.SQL_INTERVAL_HOUR_TO_MINUTE,
    IntervalHourToSecond = odbc.SQL_INTERVAL_HOUR_TO_SECOND,
    IntervalMinuteToSecond = odbc.SQL_INTERVAL_MINUTE_TO_SECOND,
    Guid = odbc.SQL_GUID,

    pub fn fromType(comptime T: type) ?SqlType {
        if (std.meta.trait.isZigString(T)) return .Varchar;
        return switch (T) {
            u8 => .Char,
            []u8 => .Varchar,
            u16 => .WChar,
            []u16 => .WVarchar,
            i8 => .TinyInt,
            i16 => .SmallInt,
            i32, u32 => .Integer,
            i64, u64 => .BigInt,
            f32 => .Float,
            f64 => .Double,
            CType.SqlDate => .Date,
            CType.SqlTime => .Time,
            CType.SqlTimestamp => .Timestamp,
            CType.SqlNumeric => .Numeric,
            CType.SqlGuid => .Guid,
            else => null
        };
    }

    pub fn defaultCType(sql_type: SqlType) CType {
        return switch (sql_type) {
            .Char => .Char,
            .Varchar => .Char,
            .LongVarchar => .Char,
            .WChar => .WChar,
            .WVarchar => .WChar,
            .WLongVarchar => .WChar,
            .Decimal => .Float,
            .Numeric => .Float,
            .SmallInt => .STinyInt,
            .Integer => .SLong,
            .Real => .Double,
            .Float => .Float,
            .Double => .Double,
            .Bit => .Bit,
            .TinyInt => .STinyInt,
            .BigInt => .SLong,
            .Binary => .Bit,
            .VarBinary => .Bit,
            .LongVarBinary => .Bit,
            .Date => .Date,
            .Time => .Time,
            .Timestamp => .Timestamp,
            .IntervalMonth => .IntervalMonth,
            .IntervalYear => .IntervalYear,
            .IntervalYearToMonth => .IntervalYearToMonth,
            .IntervalDay => .IntervalDay,
            .IntervalHour => .IntervalHour,
            .IntervalMinute => .IntervalMinute,
            .IntervalSecond => .IntervalSecond,
            .IntervalDayToHour => .IntervalDayToHour,
            .IntervalDayToMinute => .IntervalDayToMinute,
            .IntervalDayToSecond => .IntervalDayToSecond,
            .IntervalHourToMinute => .IntervalHourToMinute,
            .IntervalHourToSecond => .IntervalHourToSecond,
            .IntervalMinuteToSecond => .IntervalMinuteToSecond,
            .Guid => .Guid,
        };
    }
};

pub const StatementAttribute = enum(i32) {
    AppParamDescription = odbc.SQL_ATTR_APP_PARAM_DESC,
    AppRowDescription = odbc.SQL_ATTR_APP_ROW_DESC,
    EnableAsync = odbc.SQL_ATTR_ASYNC_ENABLE,
    AsyncStatementEvent = odbc.SQL_ATTR_ASYNC_STMT_EVENT,
    Concurrency = odbc.SQL_ATTR_CONCURRENCY,
    CursorScrollable = odbc.SQL_ATTR_CURSOR_SCROLLABLE,
    CursorSensitivity = odbc.SQL_ATTR_CURSOR_SENSITIVITY,
    CursorType = odbc.SQL_ATTR_CURSOR_TYPE,
    EnableAutoIpd = odbc.SQL_ATTR_ENABLE_AUTO_IPD,
    FetchBookmarkPointer = odbc.SQL_ATTR_FETCH_BOOKMARK_PTR,
    ImpParamDescription = odbc.SQL_ATTR_IMP_PARAM_DESC,
    ImpRowDescription = odbc.SQL_ATTR_IMP_ROW_DESC,
    KeysetSize = odbc.SQL_ATTR_KEYSET_SIZE,
    MaxLength = odbc.SQL_ATTR_MAX_LENGTH,
    MaxRows = odbc.SQL_ATTR_MAX_ROWS,
    MetadataId = odbc.SQL_ATTR_METADATA_ID,
    NoScan = odbc.SQL_ATTR_NOSCAN,
    ParamBindOffsetPointer = odbc.SQL_ATTR_PARAM_BIND_OFFSET_PTR,
    ParamBindType = odbc.SQL_ATTR_PARAM_BIND_TYPE,
    ParamOperationPointer = odbc.SQL_ATTR_PARAM_OPERATION_PTR,
    ParamStatusPointer = odbc.SQL_ATTR_PARAM_STATUS_PTR,
    ParamsProcessedPointer = odbc.SQL_ATTR_PARAMS_PROCESSED_PTR,
    ParamsetSize = odbc.SQL_ATTR_PARAMSET_SIZE,
    QueryTimeout = odbc.SQL_ATTR_QUERY_TIMEOUT,
    RetrieveData = odbc.SQL_ATTR_RETRIEVE_DATA,
    RowArraySize = odbc.SQL_ATTR_ROW_ARRAY_SIZE,
    RowBindOffsetPointer = odbc.SQL_ATTR_ROW_BIND_OFFSET_PTR,
    RowBindType = odbc.SQL_ATTR_ROW_BIND_TYPE,
    RowNumber = odbc.SQL_ATTR_ROW_NUMBER,
    RowOperationPointer = odbc.SQL_ATTR_ROW_OPERATION_PTR,
    RowStatusPointer = odbc.SQL_ATTR_ROW_STATUS_PTR,
    RowsFetchedPointer = odbc.SQL_ATTR_ROWS_FETCHED_PTR,
    SimulateCursor = odbc.SQL_ATTR_SIMULATE_CURSOR,
    UseBookmarks = odbc.SQL_ATTR_USE_BOOKMARKS,

    pub fn getValue(self: StatementAttribute, bytes: []u8) StatementAttributeValue {
        const value = bytesToValue(usize, bytes[0..@sizeOf(usize)]);
        return switch (self) {
            .AppParamDescription => .{ .AppParamDescription = @intToPtr(*c_void, value) },
            .AppRowDescription => .{ .AppRowDescription = @intToPtr(*c_void, value) },
            .EnableAsync => .{ .EnableAsync = value == odbc.SQL_ASYNC_ENABLE_ON },
            .AsyncStatementEvent => .{ .AsyncStatementEvent = @intToPtr(*c_void, value) },
            .Concurrency => .{ .Concurrency = @intToEnum(StatementAttributeValue.Concurrency, value) },
            .CursorScrollable => .{ .CursorScrollable = value == odbc.SQL_SCROLLABLE },
            .CursorSensitivity => .{ .CursorSensitivity = @intToEnum(StatementAttributeValue.CursorSensitivity, value) },
            .CursorType => .{ .CursorType = @intToEnum(StatementAttributeValue.CursorType, value) },
            .EnableAutoIpd => .{ .EnableAutoIpd = value == odbc.SQL_TRUE },
            .FetchBookmarkPointer => .{ .FetchBookmarkPointer = @intToPtr(*isize, value) },
            .ImpParamDescription => .{ .ImpParamDescription = @intToPtr(*c_void, value) },
            .ImpRowDescription => .{ .ImpRowDescription = @intToPtr(*c_void, value) },
            .KeysetSize => .{ .KeysetSize = value },
            .MaxLength => .{ .MaxLength = value },
            .MaxRows => .{ .MaxRows = value },
            .MetadataId => .{ .MetadataId = value == odbc.SQL_TRUE },
            .NoScan => .{ .NoScan = value == odbc.SQL_NOSCAN_ON },
            .ParamBindOffsetPointer => .{ .ParamBindOffsetPointer = @intToPtr(?*c_void, value) },
            .ParamBindType => .{ .ParamBindType = value },
            .ParamOperationPointer => .{ .ParamOperationPointer = @alignCast(@alignOf(usize), std.mem.bytesAsSlice(StatementAttributeValue.ParamOperation, bytes)) },
            .ParamStatusPointer => .{ .ParamStatusPointer = @alignCast(@alignOf(usize), std.mem.bytesAsSlice(StatementAttributeValue.ParamStatus, bytes)) },
            .ParamsProcessedPointer => .{ .ParamsProcessedPointer = @intToPtr(*usize, value) },
            .ParamsetSize => .{ .ParamsetSize = value },
            .QueryTimeout => .{ .QueryTimeout = value },
            .RetrieveData => .{ .RetrieveData = value == odbc.SQL_RD_ON },
            .RowArraySize => .{ .RowArraySize = value },
            .RowBindOffsetPointer => .{ .RowBindOffsetPointer = @intToPtr(*usize, value) },
            .RowBindType => .{ .RowBindType = value },
            .RowNumber => .{ .RowNumber = value },
            .RowOperationPointer => .{ .RowOperationPointer = @alignCast(@alignOf(usize), std.mem.bytesAsSlice(StatementAttributeValue.RowOperation, bytes)) },
            .RowStatusPointer => .{ .RowStatusPointer = @alignCast(@alignOf(usize), std.mem.bytesAsSlice(StatementAttributeValue.RowStatus, bytes)) },
            .RowsFetchedPointer => .{ .RowsFetchedPointer = @intToPtr(*usize, value) },
            .SimulateCursor => .{ .SimulateCursor = @intToEnum(StatementAttributeValue.SimulateCursor, value) },
            .UseBookmarks => .{ .UseBookmarks = value == odbc.SQL_UB_VARIABLE },
        };
    }

};

pub const StatementAttributeValue = union(StatementAttribute) {
    AppParamDescription: *c_void,
    AppRowDescription: *c_void,
    EnableAsync: bool,
    AsyncStatementEvent: *c_void, // @todo This is an event handle - probably more appropriate to use a function pointer
    Concurrency: Concurrency,
    CursorScrollable: bool,
    CursorSensitivity: CursorSensitivity,
    CursorType: CursorType,
    EnableAutoIpd: bool,
    FetchBookmarkPointer: *isize,
    ImpParamDescription: *c_void,
    ImpRowDescription: *c_void,
    KeysetSize: usize,
    MaxLength: usize,
    MaxRows: usize,
    MetadataId: bool,
    NoScan: bool,
    ParamBindOffsetPointer: ?*c_void,
    ParamBindType: usize,
    ParamOperationPointer: []ParamOperation,
    ParamStatusPointer: []ParamStatus,
    ParamsProcessedPointer: *usize,
    ParamsetSize: usize,
    QueryTimeout: usize,
    RetrieveData: bool,
    RowArraySize: usize,
    RowBindOffsetPointer: *usize,
    RowBindType: usize,
    RowNumber: usize,
    RowOperationPointer: []RowOperation,
    RowStatusPointer: []RowStatus,
    RowsFetchedPointer: *usize,
    SimulateCursor: SimulateCursor,
    UseBookmarks: bool,

    pub const Concurrency = enum(usize) {
        ReadOnly = odbc.SQL_CONCUR_READ_ONLY,
        Lock = odbc.SQL_CONCUR_LOCK,
        RowVersion = odbc.SQL_CONCUR_ROWVER,
        Values = odbc.SQL_CONCUR_VALUES,
    };

    pub const CursorSensitivity = enum(usize) {
        Unspecified = odbc.SQL_UNSPECIFIED,
        Insensitive = odbc.SQL_INSENSITIVE,
        Sensitive = odbc.SQL_SENSITIVE,
    };

    pub const CursorType = enum(usize) {
        ForwardOnly = odbc.SQL_CURSOR_FORWARD_ONLY,
        Static = odbc.SQL_CURSOR_STATIC,
        KeysetDriven = odbc.SQL_CURSOR_KEYSET_DRIVEN,
        Dynamic = odbc.SQL_CURSOR_DYNAMIC,
    };

    pub const ParamOperation = enum(c_ushort) {
        Proceed = odbc.SQL_PARAM_PROCEED,
        Ignore = odbc.SQL_PARAM_IGNORE
    };

    pub const ParamStatus = enum(c_ushort) {
        Success = odbc.SQL_PARAM_SUCCESS,
        SuccessWithInfo = odbc.SQL_PARAM_SUCCESS_WITH_INFO,
        Error = odbc.SQL_PARAM_ERROR,
        Unused = odbc.SQL_PARAM_UNUSED,
        DiagnosticUnavailable = odbc.SQL_PARAM_DIAG_UNAVAILABLE,
    };

    pub const RowOperation = enum(c_ushort) {
        Proceed = odbc.SQL_ROW_PROCEED,
        Ignore = odbc.SQL_ROW_IGNORE,
    };

    pub const RowStatus = enum(c_ushort) {
        Success = odbc.SQL_ROW_SUCCESS,
        SuccessWithInfo = odbc.SQL_ROW_SUCCESS_WITH_INFO,
        Error = odbc.SQL_ROW_ERROR,
        Updated = odbc.SQL_ROW_UPDATED,
        Deleted = odbc.SQL_ROW_DELETED,
        Added = odbc.SQL_ROW_ADDED,
        NoRow = odbc.SQL_ROW_NOROW,
    };

    pub const SimulateCursor = enum(usize) {
        NonUnique = odbc.SQL_SC_NON_UNIQUE,
        TryUnique = odbc.SQL_SC_TRY_UNIQUE,
        Unique = odbc.SQL_SC_UNIQUE,
    };

    pub fn valueAsBytes(attr_value: StatementAttributeValue, allocator: *std.mem.Allocator) ![]const u8 {
        const bytes: []u8 = switch (attr_value) {
            .AppParamDescription => |v| toBytes(@ptrToInt(v))[0..],
            .AppRowDescription => |v| toBytes(@ptrToInt(v))[0..],
            .EnableAsync => |v| blk: {
                const value: usize = if (v) odbc.SQL_ASYNC_ENABLE_ON else odbc.SQL_ASYNC_ENABLE_OFF;
                break :blk toBytes(value)[0..];
            },
            .AsyncStatementEvent => |v| toBytes(@ptrToInt(v))[0..],
            .Concurrency => |v| toBytes(@enumToInt(v))[0..],
            .CursorScrollable => |v| blk: {
                const value: usize = if (v) odbc.SQL_SCROLLABLE else odbc.SQL_NONSCROLLABLE;
                break :blk toBytes(value)[0..];
            },
            .CursorSensitivity => |v| toBytes(@enumToInt(v))[0..],
            .CursorType => |v| toBytes(@enumToInt(v))[0..],
            .EnableAutoIpd => |v| blk: {
                const value: usize = if (v) odbc.SQL_TRUE else odbc.SQL_FALSE;
                break :blk toBytes(value)[0..];
            },
            .FetchBookmarkPointer => |v| toBytes(@ptrToInt(v))[0..],
            .ImpParamDescription => |v| toBytes(@ptrToInt(v))[0..],
            .ImpRowDescription => |v| toBytes(@ptrToInt(v))[0..],
            .KeysetSize => |v| toBytes(v)[0..],
            .MaxLength => |v| toBytes(v)[0..],
            .MaxRows => |v| toBytes(v)[0..],
            .MetadataId => |v| blk: {
                const value: usize = if (v) odbc.SQL_TRUE else odbc.SQL_FALSE;
                break :blk toBytes(value)[0..];
            },
            .NoScan => |v| blk: {
                const value: usize = if (v) odbc.SQL_NOSCAN_ON else odbc.SQL_NOSCAN_OFF;
                break :blk toBytes(value)[0..];
            },
            .ParamBindOffsetPointer => |v| toBytes(@ptrToInt(v))[0..],
            .ParamBindType => |v| toBytes(v)[0..],
            
            .ParamsProcessedPointer => |v| toBytes(@ptrToInt(v))[0..],
            .ParamsetSize => |v| toBytes(v)[0..],
            .QueryTimeout => |v| toBytes(v)[0..],
            .RetrieveData => |v| blk: {
                const value: usize = if (v) odbc.SQL_RD_ON else odbc.SQL_RD_OFF;
                break :blk toBytes(value)[0..];
            },
            .RowArraySize => |v| toBytes(v)[0..],
            .RowBindOffsetPointer => |v| toBytes(@ptrToInt(v))[0..],
            .RowBindType => |v| toBytes(v)[0..],
            .RowNumber => |v| toBytes(v)[0..],
            .RowsFetchedPointer => |v| toBytes(@ptrToInt(v))[0..],
            .SimulateCursor => |v| toBytes(@enumToInt(v))[0..],
            .UseBookmarks => |v| blk: {
                const value: usize = if (v) odbc.SQL_UB_VARIABLE else odbc.SQL_UB_OFF;
                break :blk toBytes(value)[0..];
            },
            .ParamOperationPointer => |v| std.mem.sliceAsBytes(v)[0..],
            .ParamStatusPointer => |v| std.mem.sliceAsBytes(v)[0..],
            .RowOperationPointer => |v| std.mem.sliceAsBytes(v)[0..],
            .RowStatusPointer => |v| std.mem.sliceAsBytes(v)[0..],
        };

        var result_buffer = try allocator.alloc(u8, bytes.len);
        std.mem.copy(u8, result_buffer, bytes);

        return result_buffer;
    }
    
};

pub const InputOutputType = enum(odbc.SQLSMALLINT) {
    Input = odbc.SQL_PARAM_INPUT,
    InputOutput = odbc.SQL_PARAM_INPUT_OUTPUT,
    Output = odbc.SQL_PARAM_OUTPUT,
    InputOutputStream = odbc.SQL_PARAM_INPUT_OUTPUT_STREAM,
    OutputStream = odbc.SQL_PARAM_OUTPUT_STREAM,
};

pub const BulkOperation = enum(odbc.SQLUSMALLINT) {
    Add = odbc.SQL_ADD,
    UpdateByBookmark = odbc.SQL_UPDATE_BY_BOOKMARK,
    DeleteByBookmark = odbc.SQL_DELETE_BY_BOOKMARK,
    FetchByBookmark = odbc.SQL_FETCH_BY_BOOKMARK,
};

pub const ColumnAttribute = enum(odbc.SQLUSMALLINT) {
    AutoUniqueValue = odbc.SQL_DESC_AUTO_UNIQUE_VALUE,
    BaseColumnName = odbc.SQL_DESC_BASE_COLUMN_NAME,
    BaseTableName = odbc.SQL_DESC_BASE_TABLE_NAME,
    CaseSensitive = odbc.SQL_DESC_CASE_SENSITIVE,
    CatalogName = odbc.SQL_DESC_CATALOG_NAME,
    ConciseType = odbc.SQL_DESC_CONCISE_TYPE,
    Count = odbc.SQL_DESC_COUNT,
    DisplaySize = odbc.SQL_DESC_DISPLAY_SIZE,
    FixedPrecisionScale = odbc.SQL_DESC_FIXED_PREC_SCALE,
    Label = odbc.SQL_DESC_LABEL,
    Length = odbc.SQL_DESC_LENGTH,
    LiteralPrefix = odbc.SQL_DESC_LITERAL_PREFIX,
    LiteralSuffix = odbc.SQL_DESC_LITERAL_SUFFIX,
    LocalTypeName = odbc.SQL_DESC_LOCAL_TYPE_NAME,
    Name = odbc.SQL_DESC_NAME,
    Nullable = odbc.SQL_DESC_NULLABLE,
    NumericPrecisionRadix = odbc.SQL_DESC_NUM_PREC_RADIX,
    OctetLength = odbc.SQL_DESC_OCTET_LENGTH,
    Precision = odbc.SQL_DESC_PRECISION,
    Scale = odbc.SQL_DESC_SCALE,
    SchemaName = odbc.SQL_DESC_SCHEMA_NAME,
    Searchable = odbc.SQL_DESC_SEARCHABLE,
    TableName = odbc.SQL_DESC_TABLE_NAME,
    Type = odbc.SQL_DESC_TYPE,
    TypeName = odbc.SQL_DESC_TYPE_NAME,
    Unnamed = odbc.SQL_DESC_UNNAMED,
    Unsigned = odbc.SQL_DESC_UNSIGNED,
    Updatable = odbc.SQL_DESC_UPDATABLE,
};

pub const ColumnAttributeValue = union(ColumnAttribute) {
    AutoUniqueValue: bool,
    BaseColumnName: []const u8,
    BaseTableName: []const u8,
    CaseSensitive: bool,
    CatalogName: []const u8,
    ConciseType: SqlType,
    Count: odbc.SQLLEN,
    DisplaySize: odbc.SQLLEN,
    FixedPrecisionScale: bool,
    Label: []const u8,
    Length: odbc.SQLLEN,
    LiteralPrefix: []const u8,
    LiteralSuffix: []const u8,
    LocalTypeName: []const u8,
    Name: []const u8,
    Nullable: Nullable,
    NumericPrecisionRadix: odbc.SQLLEN,
    OctetLength: odbc.SQLLEN,
    Precision: odbc.SQLLEN,
    Scale: odbc.SQLLEN,
    SchemaName: []const u8,
    Searchable: Searchable,
    TableName: []const u8,
    Type: SqlType,
    TypeName: []const u8,
    Unnamed: bool,
    Unsigned: bool,
    Updatable: Updatable,

    pub const Searchable = enum(odbc.SQLLEN) {
        None = odbc.SQL_PRED_NONE,
        Char = odbc.SQL_PRED_CHAR,
        Basic = odbc.SQL_PRED_BASIC,
        Searchable = odbc.SQL_PRED_SEARCHABLE,
    };

    pub const Updatable = enum(odbc.SQLLEN) {
        ReadOnly = odbc.SQL_ATTR_READONLY,
        Write = odbc.SQL_ATTR_WRITE,
        Unknown = odbc.SQL_ATTR_READWRITE_UNKNOWN,
    };
};

pub const ColumnDescriptor = struct {
    name: [:0]const u8,
    data_type: SqlType,
    size: c_short,
    decimal_digits: c_short,
    nullable: Nullable,
};

pub const ParameterDescriptor = struct {
    data_type: SqlType,
    size: c_short,
    decimal_digits: c_short,
    nullable: Nullable,
};

pub const FetchOrientation = enum(odbc.SQLSMALLINT) {
    Next = odbc.SQL_FETCH_NEXT,
    Prior = odbc.SQL_FETCH_PRIOR,
    First = odbc.SQL_FETCH_FIRST,
    Last = odbc.SQL_FETCH_LAST,
    Absolute = odbc.SQL_FETCH_ABSOLUTE,
    Relative = odbc.SQL_FETCH_RELATIVE,
    Bookmark = odbc.SQL_FETCH_BOOKMARK,
};

pub const CursorOperation = enum(odbc.SQLUSMALLINT) {
    Position = odbc.SQL_POSITION,
    Refresh = odbc.SQL_REFRESH,
    Update = odbc.SQL_UPDATE,
    Delete = odbc.SQL_DELETE,
};

pub const LockType = enum(odbc.SQLUSMALLINT) {
    NoChange = odbc.SQL_LOCK_NO_CHANGE,
    Exclusive = odbc.SQL_LOCK_EXCLUSIVE,
    Unlock = odbc.SQL_LOCK_UNLOCK,
};

pub const ColumnIdentifierType = enum(odbc.SQLSMALLINT) {
    BestRowID = odbc.SQL_BEST_ROWID,
    RowVer = odbc.SQL_ROWVER,
};

pub const RowIdScope = enum(odbc.SQLSMALLINT) {
    CurrentRow = odbc.SQL_SCOPE_CURROW,
    Transaction = odbc.SQL_SCOPE_TRANSACTION,
    Session = odbc.SQL_SCOPE_SESSION,
};

pub const Reserved = enum(odbc.SQLUSMALLINT) {
    Ensure = odbc.SQL_ENSURE,
    Quick = odbc.SQL_QUICK,
};


test "CType" {
    const conforms = struct {
        fn conforms(comptime base_type: type, comptime test_type: type) bool {
            const BaseInfo = @typeInfo(base_type);

            if (std.meta.activeTag(@typeInfo(test_type)) != .Struct) return false;

            inline for (BaseInfo.Struct.fields) |field| {
                if (!@hasField(test_type, field.name)) return false;
            }

            inline for (BaseInfo.Struct.decls) |decl| {
                if (!@hasDecl(test_type, decl.name)) return false;
            }

            return true;
        }
    }.conforms;

    std.testing.refAllDecls(CType);

    const IntervalType = CType.toType(.IntervalHourToMinute);
    try std.testing.expect(conforms(CType.Interval, IntervalType));
}

test "SqlType" {
    std.testing.refAllDecls(SqlType);
}

test "SqlType to CType" {
    const c_type = SqlType.Integer.defaultCType();
    try std.testing.expect(c_type == CType.SLong);
}
