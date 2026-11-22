//! Data that lives throughout requests but gets reset after a relogin.

cur_battle: ?Battle,
entity_id_seq: u24,

const Temporaries = @This();
const std = @import("std");
const assert = std.debug.assert;

pub const init: Temporaries = .{
    .cur_battle = null,
    .entity_id_seq = 1,
};

pub const Battle = union(enum) {
    hadal: Hadal,

    pub const Kind = @typeInfo(Battle).@"union".tag_type.?;

    pub fn kind(battle: *const Battle) Kind {
        return battle.*;
    }

    pub const Hadal = struct {
        options: Options,
        room_count: u32,
        room_summary_buffer: [room_count_max]Summary,

        const room_count_max = 2;

        pub const Options = struct {
            zone_id: u32,
            layer_index: u32,
            sub_layer_index: u32,
            layer_id: u32,
            layer_item_id: u32,
            first_room_avatar_id_list: OptionalAvatarId.List,
            second_room_avatar_id_list: OptionalAvatarId.List,
            first_room_buddy_id: u32,
            second_room_buddy_id: u32,
            scene_id: u32,
            quest_id: u32,
            play_type_id: u32,
        };

        pub fn init(options: Options) Hadal {
            return .{
                .options = options,
                .room_count = 0,
                .room_summary_buffer = undefined,
            };
        }

        pub fn roomSummaries(hadal: *const Hadal) []const Summary {
            return hadal.room_summary_buffer[0..hadal.room_count];
        }

        pub fn appendRoomSummary(hadal: *Hadal, summary: Summary) error{NoSpaceLeft}!void {
            if (hadal.room_count == room_count_max) return error.NoSpaceLeft;
            defer hadal.room_count += 1;
            hadal.room_summary_buffer[hadal.room_count] = summary;
        }
    };

    pub const Summary = struct {
        avatar_count: u32,
        avatar_buffer: [avatar_count_max]Member,
        buddy_maybe: Member,

        const avatar_count_max = 3;

        pub const Member = struct {
            /// Either avatar_id or buddy_id, depending on array it was accessed from.
            template_id: u32,
            damage: u32,
            stun: u32,
            element_abnormal_accumulation: u32,
            recover: u32,
            shield: u32,
        };

        pub const init: Summary = .{
            .avatar_count = 0,
            .avatar_buffer = undefined,
            .buddy_maybe = .{
                .template_id = 0,
                .damage = 0,
                .stun = 0,
                .element_abnormal_accumulation = 0,
                .recover = 0,
                .shield = 0,
            },
        };

        pub fn buddy(summary: *const Summary) ?*const Member {
            if (summary.buddy_maybe.template_id == 0) return null;
            return &summary.buddy_maybe;
        }

        pub fn avatars(summary: *const Summary) []const Member {
            return summary.avatar_buffer[0..summary.avatar_count];
        }

        pub fn appendAvatar(summary: *Summary, member: Member) error{NoSpaceLeft}!void {
            if (summary.avatar_count == avatar_count_max) return error.NoSpaceLeft;
            defer summary.avatar_count += 1;
            summary.avatar_buffer[summary.avatar_count] = member;
        }
    };

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
