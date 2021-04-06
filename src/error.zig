const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c.zig");
const odbc = @import("types.zig");

/// Errors that can be returned from Odbc functions, as indicated by the
/// SQLRETURN value.
pub const ReturnError = error{Error, NoData, InvalidHandle, StillExecuting};

fn StringEnum(comptime E: type, comptime str_map: anytype) type {
    return struct {
        pub const Enum = E;

        pub fn fromString(str: []const u8) error{Invalid}!E {
            return inline for (str_map) |mapping| {
                if (std.mem.eql(u8, mapping[0], str)) break mapping[1];
            } else error.Invalid;
        }

        pub fn toString(enum_val: E) []const u8 {
            inline for (str_map) |mapping| {
                if (mapping[1] == enum_val) return mapping[0];
            }
            unreachable;
        }
    };
}

pub const SqlState = enum {
    Success,
    GeneralWarning,
    CursorOperationConflict,
    DisconnectError,
    NullEliminated,
    StringRightTrunc,
    PrivilegeNotRevoked,
    PrivilegeNotGranted,
    InvalidConnectionStringAttr,
    ErrorInRow,
    OptionValueChanged,
    FetchBeforeFirstResultSet,
    FractionalTruncation,
    ErrorSavingFileDSN,
    InvalidKeyword,
    WrongNumberOfParameters,
    IncorrectCountField,
    PreparedStmtNotCursorSpec,
    RestrictedDataTypeAttr,
    InvalidDescIndex,
    InvalidDefaultParam,
    ClientConnectionError,
    ConnectionNameInUse,
    ConnectionNotOpen,
    ServerRejectedConnection,
    TransactionConnectionFailure,
    CommunicationLinkFailure,
    InsertValueColumnMismatch,
    DerivedTableDegreeColumnMismatch,
    IndicatorVarRequired,
    NumOutOfRange,
    InvalidDatetimeFormat,
    DatetimeOverflow,
    DivisionByZero,
    IntervalFieldOverflow,
    InvalidCharacterValue,
    InvalidEscapeCharacter,
    InvalidEscapeSequence,
    StringLengthMismatch,
    IntegrityConstraintViolation,
    InvalidCursorState,
    InvalidTransactionState,
    TransactionState,
    TransactionStillActive,
    TransactionRolledBack,
    InvalidAuthorization,
    InvalidCursorName,
    DuplicateCursorName,
    InvalidCatalogName,
    InvalidSchemaName,
    SerializationFailure,
    StatementCompletionUnknown,
    SyntaxErrorOrAccessViolation,
    BaseTableOrViewAlreadyExists,
    BaseTableOrViewNotFound,
    IndexAlreadyExists,
    IndexNotFound,
    ColumnAlreadyExists,
    ColumnNotFound,
    WithCheckOptionViolation,
    GeneralError,
    MemoryAllocationFailure,
    InvalidAppBufferType,
    InvalidSqlDataType,
    StatementNotPrepared,
    OperationCanceled,
    InvalidNullPointer,
    FunctionSequnceError,
    AttributeCannotBeSetNow,
    InvalidTransactionOpcode,
    MemoryManagementError,
    ExcessHandles,
    NoCursorNameAvailable,
    CannotModifyImplRowDesc,
    InvalidDescHandleUse,
    ServerDeclinedCancel,
    NonCharOrBinaryDataSIP, // @note: SIP == Sent in Pieces
    AttemptToConcatNull,
    InconsistentDescInfo,
    InvalidAttributeValue,
    InvalidBufferLength,
    InvalidDescFieldIdentifier,
    InvalidAttributeIdentifier,
    FunctionTypeOutOfRange,
    InvalidInfoType,
    ColumnTypeOutOfRange,
    ScopeTypeOutOfRange,
    NullableTypeOutOfRange,
    UniquenessOptionTypeOutOfRange,
    AccuracyOptionTypeOutOfRange,
    InvalidRetrievalCode,
    InvalidPrecisionOrScaleValue,
    InvalidParamType,
    FetchTypeOutOfRange,
    RowValueOutOfRange,
    InvalidCursorPosition,
    InvalidDriverCompletion,
    InvalidBookmarkValue,
    OptionalFeatureNotImplemented,
    TimeoutExpired,
    ConnectionTimeoutExpired,
    FunctionNotSupported,
    DSNNotFound,
    DriverCouldNotBeLoaded,
    EnvHandleAllocFailed,
    ConnHandleAllocFailed,
    SetConnectionAttrFailed,
    DialogProhibited,
    DialogFailed,
    UnableToLoadTranslationDLL,
    DSNTooLong,
    DriverNameTooLong,
    DriverKeywordSyntaxError,
    TraceFileError,
    InvalidFileDSN,
    CorruptFileDataSource,
    
};

pub const OdbcError = StringEnum(SqlState, .{
    .{"00000", .Success},
    .{"01000", .GeneralWarning},
    .{"01001", .CursorOperationConflict},
    .{"01002", .DisconnectError},
    .{"01003", .NullEliminated},
    .{"01004", .StringRightTrunc},
    .{"22001", .StringRightTrunc},
    .{"01006", .PrivilegeNotRevoked},
    .{"01007", .PrivilegeNotGranted},
    .{"01S00", .InvalidConnectionStringAttr},
    .{"01S01", .ErrorInRow},
    .{"01S02", .OptionValueChanged},
    .{"01S06", .FetchBeforeFirstResultSet},
    .{"01S07", .FractionalTruncation},
    .{"01S08", .ErrorSavingFileDSN},
    .{"01S09", .InvalidKeyword},
    .{"07001", .WrongNumberOfParameters},
    .{"07002", .IncorrectCountField},
    .{"07005", .PreparedStmtNotCursorSpec},
    .{"07006", .RestrictedDataTypeAttr},
    .{"07009", .InvalidDescIndex},
    .{"07S01", .InvalidDefaultParam},
    .{"08001", .ClientConnectionError},
    .{"08002", .ConnectionNameInUse},
    .{"08004", .ServerRejectedConnection},
    .{"08007", .TransactionConnectionFailure},
    .{"08S01", .CommunicationLinkFailure},
    .{"21S01", .InsertValueColumnMismatch},
    .{"21S02", .DerivedTableDegreeColumnMismatch},
    .{"22002", .IndicatorVarRequired},
    .{"22003", .NumOutOfRange},
    .{"22007", .InvalidDatetimeFormat},
    .{"22008", .DatetimeOverflow},
    .{"22012", .DivisionByZero},
    .{"22015", .IntervalFieldOverflow},
    .{"22018", .InvalidCharacterValue},
    .{"22019", .InvalidEscapeCharacter},
    .{"22025", .InvalidEscapeSequence},
    .{"22026", .StringLengthMismatch},
    .{"23000", .IntegrityConstraintViolation},
    .{"24000", .InvalidCursorState},
    .{"25000", .InvalidTransactionState},
    .{"25S01", .TransactionState},
    .{"25S02", .TransactionStillActive},
    .{"25S03", .TransactionRolledBack},
    .{"28000", .InvalidAuthorization},
    .{"34000", .InvalidCursorName},
    .{"3C000", .DuplicateCursorName},
    .{"3D000", .InvalidCatalogName},
    .{"3F000", .InvalidSchemaName},
    .{"40001", .SerializationFailure},
    .{"40002", .IntegrityConstraintViolation},
    .{"40003", .StatementCompletionUnknown},
    .{"42000", .SyntaxErrorOrAccessViolation},
    .{"42S01", .BaseTableOrViewAlreadyExists},
    .{"42S02", .BaseTableOrViewNotFound},
    .{"42S11", .IndexAlreadyExists},
    .{"42S12", .IndexNotFound},
    .{"42S21", .ColumnAlreadyExists},
    .{"42S22", .ColumnNotFound},
    .{"44000", .WithCheckOptionViolation},
    .{"HY000", .GeneralError},
    .{"HY001", .MemoryAllocationFailure},
    .{"HY003", .InvalidAppBufferType},
    .{"HY004", .InvalidSqlDataType},
    .{"HY007", .StatementNotPrepared},
    .{"HY008", .OperationCanceled},
    .{"HY009", .InvalidNullPointer},
    .{"HY010", .FunctionSequnceError},
    .{"HY011", .AttributeCannotBeSetNow},
    .{"HY012", .InvalidTransactionOpcode},
    .{"HY013", .MemoryManagementError},
    .{"HY014", .ExcessHandles},
    .{"HY015", .NoCursorNameAvailable},
    .{"HY016", .CannotModifyImplRowDesc},
    .{"HY017", .InvalidDescHandleUse},
    .{"HY018", .ServerDeclinedCancel},
    .{"HY019", .NonCharOrBinaryDataSIP},
    .{"HY020", .AttemptToConcatNull},
    .{"HY021", .InconsistentDescInfo},
    .{"HY024", .InvalidAttributeValue},
    .{"HY090", .InvalidBufferLength},
    .{"HY091", .InvalidDescFieldIdentifier},
    .{"HY092", .InvalidAttributeIdentifier},
    .{"HY095", .FunctionTypeOutOfRange},
    .{"HY096", .InvalidInfoType},
    .{"HY097", .ColumnTypeOutOfRange},
    .{"HY098", .ScopeTypeOutOfRange},
    .{"HY099", .NullableTypeOutOfRange},
    .{"HY100", .UniquenessOptionTypeOutOfRange},
    .{"HY101", .AccuracyOptionTypeOutOfRange},
    .{"HY103", .InvalidRetrievalCode},
    .{"HY104", .InvalidPrecisionOrScaleValue},
    .{"HY105", .InvalidParamType},
    .{"HY106", .FetchTypeOutOfRange},
    .{"HY107", .RowValueOutOfRange},
    .{"HY109", .InvalidCursorPosition},
    .{"HY110", .InvalidDriverCompletion},
    .{"HY111", .InvalidBookmarkValue},
    .{"HYC00", .OptionalFeatureNotImplemented},
    .{"HYT00", .TimeoutExpired},
    .{"HYT01", .ConnectionTimeoutExpired},
    .{"IM001", .FunctionNotSupported},
    .{"IM002", .DSNNotFound},
    .{"IM003", .DriverCouldNotBeLoaded},
    .{"IM004", .EnvHandleAllocFailed},
    .{"IM005", .ConnHandleAllocFailed},
    .{"IM006", .SetConnectionAttrFailed},
    .{"IM007", .DialogProhibited},
    .{"IM008", .DialogFailed},
    .{"IM009", .UnableToLoadTranslationDLL},
    .{"IM010", .DSNTooLong},
    .{"IM011", .DriverNameTooLong},
    .{"IM012", .DriverKeywordSyntaxError},
    .{"IM013", .TraceFileError},
    .{"IM014", .InvalidFileDSN},
    .{"IM015", .CorruptFileDataSource},
});

pub const DiagnosticRecord = struct {
    sql_state: [5:0]u8,
    error_code: i32,
};

pub fn getDiagnosticRecords(allocator: *Allocator, handle_type: odbc.HandleType, handle: *c_void) ![]DiagnosticRecord {
    var num_records: u64 = 0;
    _ = c.SQLGetDiagField(@enumToInt(handle_type), handle, 0, @enumToInt(odbc.DiagnosticIdentifier.Number), &num_records, 0, null);

    var records = try allocator.alloc(DiagnosticRecord, num_records);
    errdefer allocator.free(records);
    // Diagnostic records start counting at 1
    var record_index: i16 = 1;
    while (record_index <= num_records) : (record_index += 1) {
        var record: DiagnosticRecord = undefined;
        const result = c.SQLGetDiagRec(@enumToInt(handle_type), handle, record_index, record.sql_state[0..], &@intCast(c_long, record.error_code), null, 0, null);
        switch (@intToEnum(odbc.SqlReturn, result)) {
            .Success, .SuccessWithInfo => records[@intCast(usize, record_index - 1)] = record,
            .InvalidHandle => return error.InvalidHandle,
            else => break
        }
    }

    return records;
}

pub fn getErrors(allocator: *Allocator, handle_type: odbc.HandleType, handle: *c_void) ![]SqlState {
    var num_records: u64 = 0;
    _ = c.SQLGetDiagField(@enumToInt(handle_type), handle, 0, @enumToInt(odbc.DiagnosticIdentifier.Number), &num_records, 0, null);

    var errors = try allocator.alloc(SqlState, num_records);
    errdefer allocator.free(errors);
    // Diagnostic records start counting at 1
    var record_index: i16 = 1;
    while (record_index <= num_records) : (record_index += 1) {
        var sql_state: [5:0]u8 = undefined;
        const result = c.SQLGetDiagRec(@enumToInt(handle_type), handle, record_index, sql_state[0..], null, null, 0, null);
        switch (@intToEnum(odbc.SqlReturn, result)) {
            .Success, .SuccessWithInfo => errors[@intCast(usize, record_index - 1)] = try OdbcError.fromString(&sql_state),
            .InvalidHandle => return error.InvalidHandle,
            else => break
        }
    }

    return errors;
}