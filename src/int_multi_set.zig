const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub fn IntMultiSet(comptime Int: type, comptime capacity: usize) type {
    return struct {
        count: usize,
        values: [capacity]Int,
        times: [capacity]usize,

        const Set = @This();

        pub const empty: Set = .{
            .count = 0,
            .values = undefined,
            .times = @splat(0),
        };

        pub fn putAssertCapacity(set: *Set, int: Int) void {
            if (mem.findScalar(Int, set.values[0..set.count], int)) |index| {
                set.times[index] += 1;
            } else {
                assert(set.count < capacity);
                defer set.count += 1;
                set.values[set.count] = int;
                set.times[set.count] = 1;
            }
        }

        pub fn iterator(set: *const Set) Iterator {
            return .{ .set = set, .index = 0 };
        }

        pub const Entry = struct {
            value: Int,
            times: usize,
        };

        pub const Iterator = struct {
            set: *const Set,
            index: usize,

            pub fn next(it: *Iterator) ?Entry {
                if (it.index == it.set.count) return null;
                defer it.index += 1;
                return .{
                    .value = it.set.values[it.index],
                    .times = it.set.times[it.index],
                };
            }
        };
    };
}
