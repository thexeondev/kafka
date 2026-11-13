const std = @import("std");
const ArrayList = std.ArrayList;

const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const battle = remielle.battle;
const protobuf = remielle.protobuf;
const gen = remielle.protobuf.gen;
const templates = remielle.templates;
const Configuration = remielle.Configuration;
const BoundedMultiArray = remielle.BoundedMultiArray;

const Skill = enum(u8) {
    common_attack = 0,
    special_attack = 1,
    evade = 2,
    cooperate_skill = 3,
    unique_skill = 4,
    core_skill = 5,
    assist_skill = 6,
};

const skills: [@typeInfo(Skill).@"enum".field_names.len]gen.AvatarSkillLevel = skills: {
    const skill_types = std.enums.values(Skill);
    var array: [skill_types.len]gen.AvatarSkillLevel = undefined;

    for (&array, skill_types) |*skill_level, skill_type|
        skill_level.* = .{
            .skill_type = @backingInt(skill_type),
            .level = switch (skill_type) {
                .core_skill => 7,
                else => 12,
            },
        };

    break :skills array;
};

pub const AvatarInfoList = BoundedMultiArray(struct {
    avatar_info: gen.AvatarInfo,
    dressed_equip_buffer: [Player.Storage.Avatar.equipment_count]gen.DressedEquip,
    mindscape_tab_state: [Player.Storage.Avatar.Mindscape.unlocked_max]bool,
}, Player.Storage.Avatar.count_max);

pub fn avatarInfo(out: AvatarInfoList.Ptr, avatar: Player.Avatar) void {
    var dressed_equip_list: ArrayList(gen.DressedEquip) = .initBuffer(out.dressed_equip_buffer);
    for (std.enums.values(Player.Equipment.Type)) |equipment_type| {
        const uid = avatar.dressed_equipment.get(equipment_type) orelse continue;

        dressed_equip_list.appendAssumeCapacity(.{
            .index = @backingInt(equipment_type),
            .equip_uid = uid,
        });
    }

    out.mindscape_tab_state.* = avatar.mindscape_tab.switches;

    out.avatar_info.* = .{
        .id = avatar.id,
        .level = avatar.level,
        .rank = avatar.rank,
        .is_favorite = avatar.favorite,
        .cur_weapon_uid = avatar.weapon_uid_maybe orelse 0,
        .unlocked_talent_num = avatar.unlocked_talent_num,
        .mindscape_tab_state = out.mindscape_tab_state,
        .skill_type_level = &skills,
        .passive_skill_level = 6,
        .dressed_equip_list = dressed_equip_list.items,
        .show_weapon_type = switch (avatar.weapon_show) {
            .locked => .LOCKED,
            .unlocked_show => .SHOW,
            .unlocked_hidden => .HIDE,
        },
        .is_awake_available = templates.AvatarSpecialAwaken.isAvailableForAvatar(avatar.id),
        .is_awake_enabled = avatar.awake_enabled,
        .awake_id = if (avatar.awake_index_maybe) |awake_index| awake_id: {
            const template = templates.AvatarSpecialAwaken.getByAvatarIdAndIndex(
                avatar.id,
                awake_index,
            ).?;
            break :awake_id template.id;
        } else 0,
    };
}

pub fn weaponInfo(
    out: *gen.WeaponInfo,
    kv: Player.Weapon.KeyValue,
) void {
    out.* = .{
        .uid = kv.uid,
        .id = kv.weapon.id,
        .level = 60,
        .star = 5,
        .refine_level = kv.weapon.refine,
    };
}

pub const EquipInfoList = BoundedMultiArray(struct {
    equip_info: gen.EquipInfo,
    main_property: gen.EquipProperty,
    sub_properties_buffer: [Player.Storage.Equipment.Property.sub_count]gen.EquipProperty,
}, Player.Storage.Equipment.count_max);

pub fn equipInfo(out: EquipInfoList.Ptr, kv: Player.Equipment.KeyValue) void {
    out.main_property.* = .{
        .key = kv.equipment.main_property.key,
        .base_value = kv.equipment.main_property.base,
        .add_value = kv.equipment.main_property.add,
    };

    var sub_property_list: ArrayList(gen.EquipProperty) =
        .initBuffer(out.sub_properties_buffer);

    for (kv.equipment.sub_properties) |property_maybe| {
        const property = property_maybe orelse continue;
        sub_property_list.appendAssumeCapacity(.{
            .key = property.key,
            .base_value = property.base,
            .add_value = property.add,
        });
    }

    out.equip_info.* = .{
        .uid = kv.uid,
        .id = kv.equipment.id,
        .level = 15,
        .star = 5,
        .propertys = out.main_property[0..1],
        .sub_propertys = sub_property_list.items,
    };
}

pub const HallOptions = struct {
    main_city: *const Player.Storage.MainCity,
    role: *const Player.Storage.Role,
    time: *const Player.Storage.Time,
};

pub const HallBuffer = struct {
    npcs: BoundedMultiArray(struct {
        npc_info: gen.NpcInfo,
        interact_info: protobuf.KeyValue(u32, gen.InteractInfo),
        interact_target: gen.InteractTarget,
    }, npc_count_max),

    const npc_count_max = templates.MainCityDefaultObject.table.count;
};

pub fn sceneDataForHall(options: HallOptions, buffer: *HallBuffer) gen.SceneData {
    return .{
        .scene_type = 1, // hall
        .hall_scene_data = hall(gen.HallSceneData, options, buffer),
    };
}

pub fn hall(comptime Root: type, options: HallOptions, buffer: *HallBuffer) Root {
    const main_city_section_id = @backingInt(options.main_city.section);

    for (templates.MainCityDefaultObject.table.items(.tag)) |object_tag| {
        const object_template_index = templates.MainCityObject.table.getIndexByKey(object_tag) orelse
            continue;

        const transform_name = templates.MainCityObject.table.getString(
            templates.MainCityObject.table.items(.create_position)[object_template_index],
        );

        const transform_index = templates.NpcTransform.getIndexByName(transform_name) orelse
            continue;

        const object_section_id = templates.NpcTransform.table.items(.section_id)[transform_index];
        if (object_section_id != main_city_section_id) continue;

        const data = buffer.npcs.addOneAssumeCapacity();

        const default_interact_ids =
            templates.MainCityObject.table.items(.default_interact_ids)[object_template_index];

        var interacts: ArrayList(protobuf.KeyValue(u32, gen.InteractInfo)) =
            .initBuffer(data.interact_info[0..1]);

        if (default_interact_ids[0].unwrap()) |interact_id| {
            data.interact_target.* = @fromBackingInt(2); // NPC

            interacts.appendAssumeCapacity(.{
                .key = interact_id,
                .value = .{
                    .tag_id = @intCast(object_tag),
                    .interact_target_list = data.interact_target[0..1],
                    .scale_x = 1,
                    .scale_y = 1,
                    .scale_z = 1,
                    .scale_w = 1,
                    .scale_r = 1,
                },
            });
        }

        data.npc_info.* = .{
            .npc_id = object_tag,
            .is_active = true,
            .interacts_info = interacts.items,
        };
    }

    return .{
        .section_id = main_city_section_id,
        .control_avatar_id = @backingInt(options.role.control_avatar),
        .control_guise_avatar_id = @backingInt(options.role.control_guise_avatar),
        .day_of_week = @backingInt(options.time.day),
        .scene_time_in_minutes = options.time.period.toMinutes(),
        .npc_list = buffer.npcs.items(.npc_info),
    };
}

pub fn selfBasicInfo(role: *const Player.Storage.Role) gen.SelfBasicInfo {
    return .{
        .nick_name = "xeondev",
        .level = 1,
        .name_change_times = 1,
        .avatar_id = @backingInt(role.avatar),
        .control_avatar_id = @backingInt(role.control_avatar),
        .control_guise_avatar_id = @backingInt(role.control_guise_avatar),
    };
}

pub const AvatarUnitInfoList = BoundedMultiArray(struct {
    info: gen.AvatarUnitInfo,
    properties_buffer: [battle.Property.count]protobuf.KeyValue(u32, i32),
}, Player.Storage.Avatar.count_max);

pub fn avatarUnitInfo(
    out: AvatarUnitInfoList.Ptr,
    id: u32,
    property_map: *const battle.Property.Map,
) void {
    var properties: ArrayList(protobuf.KeyValue(u32, i32)) = .initBuffer(out.properties_buffer);
    for (&property_map.values, 0..) |property_value, property_index_int| {
        const property: battle.Property = .fromIndex(@fromBackingInt(@intCast(property_index_int)));
        properties.appendAssumeCapacity(.{
            .key = @backingInt(property),
            .value = property_value,
        });
    }

    out.info.* = .{
        .avatar_id = id,
        .properties = properties.items,
    };
}

pub const HadalEntranceList = BoundedMultiArray(struct {
    info: gen.HadalEntranceInfo,
    layers_buffer: [10]gen.LayerRecord,
}, Configuration.Hadal.EntranceId.count);

pub const HadalEntranceOptions = struct {
    entrance_id: u32,
    entrance_type: i32,
    zone_id: u32,
    begin_timestamp: i64,
    end_timestamp: i64,
};

pub fn hadalEntrance(
    out: HadalEntranceList.Ptr,
    options: HadalEntranceOptions,
) void {
    var layers: ArrayList(protobuf.gen.LayerRecord) = .initBuffer(out.layers_buffer);

    for (
        templates.ZoneInfo.table.items(.id),
        templates.ZoneInfo.table.items(.layer_index),
    ) |template_id, layer_index| {
        if (template_id == options.zone_id) layers.appendAssumeCapacity(.{
            .layer_index = layer_index,
            .status = @fromBackingInt(4),
        });
    }

    out.info.* = .{
        .entrance_type = @fromBackingInt(options.entrance_type),
        .entrance_id = options.entrance_id,
        .state = @fromBackingInt(3),
        .cur_zone_record = .{
            .zone_id = options.zone_id,
            .begin_timestamp = options.begin_timestamp,
            .end_timestamp = options.end_timestamp,
            .layer_record_list = layers.items,
        },
    };
}

pub const DungeonPackageBuffer = struct {
    avatars: AvatarInfoList,
    weapons: [Player.Storage.Weapon.count_max]gen.WeaponInfo,
    equips: EquipInfoList,

    pub const init: DungeonPackageBuffer = .{
        .avatars = .empty,
        .weapons = undefined,
        .equips = .empty,
    };
};

pub fn dungeonPackage(
    buffer: *DungeonPackageBuffer,
    avatars: *Player.Avatar.Iterator,
    weapons: *Player.Weapon.KeyValue.Iterator,
    equipment: *Player.Equipment.KeyValue.Iterator,
) gen.DungeonPackageInfo {
    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(buffer.avatars.addOneAssumeCapacity(), avatar);

    var weapon_list: ArrayList(gen.WeaponInfo) = .initBuffer(&buffer.weapons);
    while (weapons.next()) |weapon_kv| {
        protobuf.pack.weaponInfo(
            weapon_list.addOneAssumeCapacity(),
            weapon_kv,
        );
    }

    while (equipment.next()) |equipment_kv| {
        protobuf.pack.equipInfo(
            buffer.equips.addOneAssumeCapacity(),
            equipment_kv,
        );
    }

    return .{
        .avatar_list = buffer.avatars.items(.avatar_info),
        .weapon_list = weapon_list.items,
        .equip_list = buffer.equips.items(.equip_info),
    };
}
