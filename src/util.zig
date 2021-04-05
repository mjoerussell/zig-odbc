const std = @import("std");

pub fn Bitmask(comptime BackingType: type, comptime fields: anytype) type {
    const BaseStruct = packed struct {};
    var base_struct_info = @typeInfo(BaseStruct);

    var incoming_fields: [fields.len]std.builtin.TypeInfo.StructField = undefined;
    inline for (fields) |field, i| {
        incoming_fields[i] = .{
            .name = field[0],
            .field_type = bool,
            .default_value = false,
            .is_comptime = false,
            .alignment = @alignOf(bool)
        };
    }

    base_struct_info.Struct.fields = incoming_fields[0..];

    const BitmaskFields = @Type(base_struct_info);

    return struct{
        pub const Result = BitmaskFields;

        /// Given a masked value, create an instance of the bitmask fields struct
        /// with the appropriate fields set to "true" based on the input value.
        pub fn applyBitmask(value: BackingType) callconv(.Inline) Result {
            var result = Result{};
            inline for (fields) |field, i| {
                if (value & field[1] == field[1]) {
                    @field(result, field[0]) = true;
                }
            }

            return result;
        }

        /// Given a bitmask field struct, generate a masked value using the configured mask values
        /// for each field.
        pub fn createBitmask(bitmask_fields: BitmaskFields) callconv(.Inline) BackingType {
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

/// Initialize a tagged union with a comptime-known enum value. This is just a thin wrapper over the builtin function @unionInit.
pub fn unionInitEnum(comptime U: type, comptime E: std.meta.Tag(U), value: std.meta.TagPayload(U, E)) callconv(.Inline) U {
    return @unionInit(U, @tagName(E), value);
}

pub fn sliceToValue(comptime T: type, slice: []u8) callconv(.Inline) T {
    const ptr = @ptrCast(*const [@sizeOf(T)]u8, slice[0..@sizeOf(T)]);
    return std.mem.bytesToValue(T, ptr);
}

test "bitmask" {
    const TestType = Bitmask(u4, .{
        .{ "fieldA", 0b0001 }, 
        .{ "fieldB", 0b0010 },
        .{ "fieldC", 0b0100 }
    });

    const test_value = TestType.applyBitmask(0b0110);

    std.testing.expect(!test_value.fieldA);
    std.testing.expect(test_value.fieldB);
    std.testing.expect(test_value.fieldC);

    const test_set: TestType.Result = .{
        .fieldA = true,
        .fieldB = false,
        .fieldC = true
    };

    const test_set_result = TestType.createBitmask(test_set);

    std.testing.expectEqual(@as(u4, 0b0101), test_set_result);
}