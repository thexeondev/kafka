const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub fn StaticIntMap(comptime Key: type, comptime Value: type) type {
    assert(@typeInfo(Key) == .int);

    return struct {
        keys: []const Key,
        values: []const Value,

        const Map = @This();

        pub const Tuple = struct { Key, Value };

        pub inline fn initComptime(comptime kvs: []const Tuple) Map {
            comptime {
                var keys: [kvs.len]Key = undefined;
                var values: [kvs.len]Value = undefined;

                @setEvalBranchQuota(kvs.len);
                for (&keys, &values, kvs) |*k, *v, kv| {
                    const key, const value = kv;

                    k.* = key;
                    v.* = value;
                }

                const keys_final = keys;
                const values_final = values;

                return .{ .keys = &keys_final, .values = &values_final };
            }
        }

        pub fn get(map: *const Map, key: Key) ?Value {
            const index = mem.findScalar(Key, map.keys, key) orelse return null;
            return map.values[index];
        }
    };
}
