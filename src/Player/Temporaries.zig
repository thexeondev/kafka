//! Data that lives throughout requests but gets reset after a relogin.

cur_battle: ?Battle,
view_objects: ?ViewObjects,

const Temporaries = @This();
const std = @import("std");
const assert = std.debug.assert;

const remielle = @import("../remielle.zig");
const assets = remielle.assets;

pub const init: Temporaries = .{
    .cur_battle = null,
    .view_objects = null,
};

pub const ViewObjects = struct {
    master_entity_id: EntityId,
    entity_id_seq: u24,
    groups: Groups,

    pub fn init(vo: *ViewObjects, group_id_list: []const u32) void {
        vo.master_entity_id = .{ .seqn = 1, .type = .avatar };
        vo.entity_id_seq = 2;
        vo.groups.init(group_id_list);
    }

    pub fn nextEntityId(vo: *ViewObjects, @"type": EntityId.Type) EntityId {
        defer vo.entity_id_seq +%= 1;
        return .{ .type = @"type", .seqn = vo.entity_id_seq };
    }

    pub const EntityId = packed struct(u32) {
        seqn: u24,
        type: Type,

        pub const Type = enum(u8) {
            avatar = 1,
            monster = 2,
            gadget = 7,
            _,
        };

        pub fn toInt(id: EntityId) u32 {
            return @backingInt(id);
        }
    };

    pub const Groups = struct {
        buffer: [count_max]u32,
        inactive_count: u32,
        active_count: u32,
        ready_count: u32,

        pub const count_max = assets.Group.table.group_ids.len;

        pub fn init(groups: *Groups, group_id_list: []const u32) void {
            assert(count_max >= group_id_list.len);

            @memcpy(groups.buffer[0..group_id_list.len], group_id_list);
            groups.inactive_count = @intCast(group_id_list.len);
            groups.active_count = 0;
            groups.ready_count = 0;
        }

        pub fn inactive(groups: *Groups) InactiveIterator {
            return .{ .groups = groups, .next_index = 0 };
        }

        pub const InactiveIterator = struct {
            groups: *Groups,
            next_index: u32,

            pub fn next(it: *InactiveIterator) ?u32 {
                if (it.next_index >= it.groups.inactive_count) return null;

                defer it.next_index += 1;
                return it.groups.buffer[it.next_index];
            }

            /// Activates group previously returned from `next`.
            pub fn activate(it: *InactiveIterator) void {
                assert(it.next_index != 0);
                assert(it.groups.inactive_count != 0);
                defer it.next_index -= 1;

                const inactive_index = it.next_index - 1;
                const group_id = it.groups.buffer[inactive_index];
                it.groups.buffer[inactive_index] = it.groups.buffer[it.groups.inactive_count - 1];
                it.groups.inactive_count -= 1;

                it.groups.active_count += 1;
                const active_index = count_max - it.groups.active_count;
                it.groups.buffer[active_index] = group_id;
            }
        };

        pub fn flushGroupOrders(groups: *Groups) []const u32 {
            assert(groups.active_count >= groups.ready_count);
            defer groups.ready_count = groups.active_count;

            const orders_count = groups.active_count - groups.ready_count;
            const active_start = count_max - groups.active_count;

            return groups.buffer[active_start..][0..orders_count];
        }
    };
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
