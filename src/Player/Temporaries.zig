//! Data that lives throughout requests but gets reset after a relogin.

last_hadal_battle_options: ?HadalBattleOptions,

const Temporaries = @This();
const std = @import("std");
const assert = std.debug.assert;

pub const init: Temporaries = .{
    .last_hadal_battle_options = null,
};

pub const HadalBattleOptions = struct {
    zone_id: u32,
    layer_index: u32,
    layer_item_id: u32,
    room_index: u32,
    first_room_avatar_id_list: OptionalAvatarId.List,
    second_room_avatar_id_list: OptionalAvatarId.List,
    first_room_buddy_id: u32,
    second_room_buddy_id: u32,
    scene_id: u32,
    quest_id: u32,
    play_type_id: u32,

    pub const OptionalAvatarId = enum(u32) {
        none = 0,
        _,

        pub fn wrap(avatar_id: u32) OptionalAvatarId {
            assert(avatar_id != 0);
            return @fromBackingInt(avatar_id);
        }

        pub fn unwrap(optional: OptionalAvatarId) ?u32 {
            return switch (optional) {
                .none => null,
                else => |id| @backingInt(id),
            };
        }

        pub const List = struct {
            optionals: [count_max]OptionalAvatarId,

            pub const count_max = 3;

            pub fn fromSlice(slice: []const u32) List {
                assert(slice.len <= count_max);
                var result: List = .{ .optionals = @splat(.none) };

                for (result.optionals[0..slice.len], slice) |*optional, avatar_id|
                    optional.* = .wrap(avatar_id);

                return result;
            }

            pub fn toSlice(list: *const List) []const u32 {
                var count: u32 = 0;
                while (count < count_max) {
                    if (list.optionals[count] == .none) break;
                    count += 1;
                }

                return @ptrCast(list.optionals[0..count]);
            }
        };
    };
};
