const std = @import("std");
const mem = std.mem;

const Slice = extern struct {
    offset: u32,
    len: u32,

    fn take(slice: Slice, table: anytype) []const @typeInfo(@TypeOf(table)).pointer.child {
        return table[slice.offset..][0..slice.len];
    }
};

const ConfigFloorHeader = extern struct {
    floor_count: u32,
    ids_offset: u32,
    metadata_offset: u32,
    group_ids_offset: u32,
    strings_offset: u32,
};

const FloorMetadata = extern struct {
    scene_config_id: u32,
    group_id_list: Slice,
    floor_md5: Slice,
};

inline fn ptrCast(comptime T: type, bytes: [*]const u8) [*]const T {
    return @ptrCast(@alignCast(bytes));
}

pub const Floor = struct {
    id: u32,
    scene_config_id: u32,
    group_id_list: []const u32,
    md5: []const u8,

    pub const table = struct {
        const bytes align(@alignOf(u32)) = @embedFile("assets/LevelWorld/bin/ConfigFloor.bin");
        const header: *const ConfigFloorHeader =
            @ptrCast(@alignCast(bytes[0..@sizeOf(ConfigFloorHeader)]));

        pub const ids: []const u32 =
            ptrCast(u32, bytes[header.ids_offset..].ptr)[0..header.floor_count];

        pub fn get(floor_id: u32) ?Floor {
            const index = mem.findScalar(u32, ids[0..header.floor_count], floor_id) orelse
                return null;

            const metadata_list = ptrCast(FloorMetadata, bytes[header.metadata_offset..].ptr);
            const metadata = metadata_list[index];

            const group_ids = ptrCast(u32, bytes[header.group_ids_offset..].ptr);
            const strings = ptrCast(u8, bytes[header.strings_offset..].ptr);

            return .{
                .id = floor_id,
                .scene_config_id = metadata.scene_config_id,
                .group_id_list = metadata.group_id_list.take(group_ids),
                .md5 = metadata.floor_md5.take(strings),
            };
        }
    };
};

const ConfigGroupHeader = extern struct {
    group_count: u32,
    group_id_offset: u32,
    group_metadata_offset: u32,
    battle_region_areas_offset: u32,
    monster_count: u32,
    monster_config_ids_offset: u32,
    monster_ids_offset: u32,
    monster_positions_offset: u32,
    gadget_count: u32,
    gadget_ids_offset: u32,
    gadget_config_ids_offset: u32,
    gadget_positions_offset: u32,
    gadget_types_offset: u32,
    monster_id_types_offset: u32,
};

const GroupMetadata = extern struct {
    vo_group_type: u32,
    group_usage: u32,
    gadgets: Slice,
    monsters: Slice,
    battle_region_areas: Slice,
};

pub const Position = extern struct {
    x: i32,
    y: i32,
    z: i32,
    euler_y: i32,
};

pub const GadgetType = enum(u8) {
    default = 0,
    portal = 1,
    view_point = 2,
    treasure = 3,
    collection = 4,
    _,
};

pub const MonsterIdType = enum(u8) {
    base_id = 0,
    sub_id = 1,
};

const Polygon = extern struct {
    height_y: i32,
    origin_pos: extern struct {
        x: i32,
        y: i32,
        z: i32,
    },
};

pub const Group = struct {
    id: u32,
    monster_config_ids: []const u32,
    monster_ids: []const i32,
    monster_positions: []const Position,
    monster_id_types: []const MonsterIdType,
    gadget_ids: []const i32,
    gadget_config_ids: []const u32,
    gadget_positions: []const Position,
    gadget_types: []const GadgetType,

    pub const Metadata = struct {
        vo_group_type: u32,
        group_usage: u32,
        battle_region_areas: []const Polygon,
    };

    pub fn configIdVec(group: *const Group) [2][]const u32 {
        return .{ group.gadget_config_ids, group.monster_config_ids };
    }

    pub const table = struct {
        const bytes align(@alignOf(u32)) = @embedFile("assets/LevelWorld/bin/ConfigGroup.bin");
        const header: *const ConfigGroupHeader =
            @ptrCast(@alignCast(bytes[0..@sizeOf(ConfigGroupHeader)]));

        pub const group_ids: []const u32 =
            ptrCast(u32, bytes[header.group_id_offset..].ptr)[0..header.group_count];

        pub const monster_config_ids: []const u32 =
            ptrCast(u32, bytes[header.monster_config_ids_offset..].ptr)[0..header.monster_count];

        pub const monster_ids: []const i32 =
            ptrCast(i32, bytes[header.monster_ids_offset..].ptr)[0..header.monster_count];

        pub const monster_positions: []const Position =
            ptrCast(Position, bytes[header.monster_positions_offset..].ptr)[0..header.monster_count];

        pub const gadget_ids: []const i32 =
            ptrCast(i32, bytes[header.gadget_ids_offset..].ptr)[0..header.gadget_count];

        pub const gadget_config_ids: []const u32 =
            ptrCast(u32, bytes[header.gadget_config_ids_offset..].ptr)[0..header.gadget_count];

        pub const gadget_positions: []const Position =
            ptrCast(Position, bytes[header.gadget_positions_offset..].ptr)[0..header.gadget_count];

        pub const gadget_types: []const GadgetType =
            ptrCast(GadgetType, bytes[header.gadget_types_offset..].ptr)[0..header.gadget_count];

        pub const monster_id_types: []const MonsterIdType =
            ptrCast(MonsterIdType, bytes[header.monster_id_types_offset..].ptr)[0..header.monster_count];

        pub fn getGroupById(group_id: u32) ?Group {
            const group_index = mem.findScalar(u32, group_ids, group_id) orelse
                return null;

            const group_metadata =
                ptrCast(GroupMetadata, bytes[header.group_metadata_offset..])[group_index];

            return .{
                .id = group_id,
                .monster_config_ids = group_metadata.monsters.take(monster_config_ids),
                .monster_ids = group_metadata.monsters.take(monster_ids),
                .monster_positions = group_metadata.monsters.take(monster_positions),
                .monster_id_types = group_metadata.monsters.take(monster_id_types),
                .gadget_ids = group_metadata.gadgets.take(gadget_ids),
                .gadget_config_ids = group_metadata.gadgets.take(gadget_config_ids),
                .gadget_positions = group_metadata.gadgets.take(gadget_positions),
                .gadget_types = group_metadata.gadgets.take(gadget_types),
            };
        }

        pub fn getGroupMetadata(group_id: u32) ?Group.Metadata {
            const group_index = mem.findScalar(u32, group_ids, group_id) orelse
                return null;

            const group_metadata =
                ptrCast(GroupMetadata, bytes[header.group_metadata_offset..])[group_index];

            const battle_region_areas =
                ptrCast(Polygon, bytes[header.battle_region_areas_offset..]);

            return .{
                .vo_group_type = group_metadata.vo_group_type,
                .group_usage = group_metadata.group_usage,
                .battle_region_areas = group_metadata.battle_region_areas.take(battle_region_areas),
            };
        }
    };
};
