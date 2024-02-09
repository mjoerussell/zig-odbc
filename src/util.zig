const std = @import("std");
const Type = std.builtin.Type;

pub fn Bitmask(comptime BackingType: type, comptime fields: anytype) type {
    var incoming_fields: [fields.len]Type.StructField = undefined;
    inline for (fields, 0..) |field, i| {
        incoming_fields[i] = .{ .name = field[0], .type = bool, .default_value = &false, .is_comptime = false, .alignment = @alignOf(bool) };
    }

    const BitmaskFields = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = incoming_fields[0..],
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
    } });

    return struct {
        pub const Result = BitmaskFields;

        /// Given a masked value, create an instance of the bitmask fields struct
        /// with the appropriate fields set to "true" based on the input value.
        pub inline fn applyBitmask(value: BackingType) Result {
            var result = Result{};
            inline for (fields) |field| {
                if (value & field[1] == field[1]) {
                    @field(result, field[0]) = true;
                }
            }

            return result;
        }

        /// Given a bitmask field struct, generate a masked value using the configured mask values
        /// for each field.
        pub inline fn createBitmask(bitmask_fields: BitmaskFields) BackingType {
            var result: BackingType = 0;

            inline for (fields) |field| {
                if (@field(bitmask_fields, field[0])) {
                    result |= field[1];
                }
            }

            return result;
        }
    };
}

pub fn EnumErrorSet(comptime BaseEnum: type) type {
    switch (@typeInfo(BaseEnum)) {
        .Enum => |info| {
            var error_set: [info.fields.len]Type.Error = undefined;
            inline for (info.fields, 0..) |field, index| {
                error_set[index] = .{ .name = field.name };
            }

            return @Type(Type{ .ErrorSet = error_set[0..] });
        },
        else => @compileError("EnumErrorSet requires an enum, found " ++ @typeName(BaseEnum)),
    }
}

/// Initialize a tagged union with a comptime-known enum value. This is just a thin wrapper over the builtin function @unionInit.
pub inline fn unionInitEnum(comptime U: type, comptime E: std.meta.Tag(U), value: std.meta.TagPayload(U, E)) U {
    return @unionInit(U, @tagName(E), value);
}

pub inline fn sliceToValue(comptime T: type, slice: []u8) T {
    const ptr = @as(*const [@sizeOf(T)]u8, @ptrCast(slice[0..@sizeOf(T)]));
    return std.mem.bytesToValue(T, ptr);
}

test "bitmask" {
    const TestType = Bitmask(u4, .{ .{ "fieldA", 0b0001 }, .{ "fieldB", 0b0010 }, .{ "fieldC", 0b0100 } });

    const test_value = TestType.applyBitmask(0b0110);

    try std.testing.expect(!test_value.fieldA);
    try std.testing.expect(test_value.fieldB);
    try std.testing.expect(test_value.fieldC);

    const test_set: TestType.Result = .{ .fieldA = true, .fieldB = false, .fieldC = true };

    const test_set_result = TestType.createBitmask(test_set);

    try std.testing.expectEqual(@as(u4, 0b0101), test_set_result);
}

test "enum error" {
    const Base = enum { A, B, C };
    const BaseError = EnumErrorSet(Base);

    try std.testing.expectEqual(BaseError, error{ A, B, C });

    // Just making sure everything compiles, that BaseError is accepted in the error
    // spot of the return type.
    // The actual logic below is pretty basic and not really the point here
    const test_func = (struct {
        pub fn f() BaseError!void {
            return BaseError.B;
        }
    }).f;

    try std.testing.expectError(BaseError.B, test_func());
}
