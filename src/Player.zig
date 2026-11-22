storage: *Storage,
temp: *Temporaries,
needs_save: bool,
sync: Sync,

const Player = @This();
const std = @import("std");
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

pub const Zon = @import("Player/Zon.zig");
pub const Storage = @import("Player/Storage.zig");
pub const Temporaries = @import("Player/Temporaries.zig");

const remielle = @import("remielle.zig");
const gen = remielle.protobuf.gen;
const pack = remielle.protobuf.pack;
const features = remielle.protobuf.features;
const battle = remielle.battle;
const assets = remielle.assets;

pub const Sync = struct {
    needs_player_sync_notify: bool,
    avatar_list: pack.AvatarInfoList,
    control_guise_avatar_changed: bool,
    scene: Scene, // Not sure if this belongs here. Maybe `Sync` needs a better name.
    buffers: Buffers,
    big_scene_team_replaced: ?struct {
        prev: BigSceneTeam,
    },

    pub const Scene = struct {
        reload_hall_scene: bool,
        time_modified: bool,
        reload_big_scene_floor: bool,
        big_scene_logic_started: bool,

        hall_buffer: pack.HallBuffer,
    };

    pub const Buffers = struct {
        big_scene_avatar_minimal: if (features.big_scene_avatars)
            [Storage.Avatar.count_max]gen.BigSceneAvatarInfo
        else
            void,
        big_scene_avatar_team: pack.BigSceneAvatarList,
    };

    pub const init: Sync = .{
        .needs_player_sync_notify = false,
        .avatar_list = .empty,
        .control_guise_avatar_changed = false,
        .big_scene_team_replaced = null,
        .buffers = .{
            .big_scene_avatar_minimal = undefined,
            .big_scene_avatar_team = .empty,
        },
        .scene = .{
            .reload_hall_scene = false,
            .time_modified = false,
            .reload_big_scene_floor = false,
            .big_scene_logic_started = false,
            .hall_buffer = .{ .npcs = .empty },
        },
    };
};

pub const Avatar = struct {
    id: u32,
    level: u32,
    rank: u32,
    unlocked_talent_num: u32,
    mindscape_tab: MindscapeTab,
    favorite: bool,
    weapon_show: WeaponShow,
    weapon_uid_maybe: ?u32,
    dressed_equipment: DressedEquipment,
    awake_index_maybe: ?u3,
    awake_enabled: bool,
    skin_id_maybe: ?u32,
    form_id_maybe: ?u32,

    pub const DressedEquipment = std.EnumMap(Equipment.Type, u32);

    pub const Iterator = struct {
        index: u32,
        player: *const Player,

        pub fn next(it: *Iterator) ?Avatar {
            if (it.player.storage.avatars.count == it.index) return null;
            defer it.index += 1;

            return it.player.avatarAtIndex(it.index);
        }
    };

    pub const WeaponShow = enum {
        locked,
        unlocked_show,
        unlocked_hidden,
    };

    pub const MindscapeTab = struct {
        switches: [switch_count]bool,

        const switch_count = 6;

        pub fn fromSlice(slice: []const bool) ?MindscapeTab {
            if (slice.len != switch_count) return null;

            const switches = slice[0..switch_count].*;
            for (switches[0..3], switches[3..6]) |a, b|
                if (a and b) return null;

            return .{ .switches = switches };
        }

        pub fn requiredUnlock(tab: *const MindscapeTab) u32 {
            var required_unlock: u32 = 6;
            while (required_unlock > 0 and !tab.switches[required_unlock - 1]) {
                required_unlock -= 1;
            }

            return required_unlock;
        }
    };
};

pub const Weapon = struct {
    id: u32,
    refine: u32,

    pub const KeyValue = struct {
        uid: u32,
        weapon: Weapon,

        pub const Iterator = struct {
            index: u32,
            player: *const Player,

            pub fn next(it: *Iterator) ?Weapon.KeyValue {
                if (it.player.storage.weapons.count == it.index) return null;
                defer it.index += 1;

                return it.player.weaponAtIndex(it.index);
            }
        };
    };
};

pub const Equipment = struct {
    id: u32,
    main_property: Property,
    sub_properties: [sub_property_count]?Property,

    pub const sub_property_count = 4;

    pub const Property = struct {
        key: u16,
        base: u16,
        add: u16,

        fn fromStorage(storage: *const Storage.Equipment.Property) Property {
            return .{
                .key = @backingInt(storage.key),
                .base = storage.base,
                .add = storage.add,
            };
        }

        fn fromStorageOptional(optional: *const Storage.Equipment.Property.Optional) ?Property {
            return if (optional.unwrap()) |storage| .fromStorage(&storage) else null;
        }
    };

    pub const Type = enum(u8) {
        @"1" = 1,
        @"2" = 2,
        @"3" = 3,
        @"4" = 4,
        @"5" = 5,
        @"6" = 6,

        pub const count = 6;
    };

    pub const KeyValue = struct {
        uid: u32,
        equipment: Equipment,

        pub const Iterator = struct {
            index: u32,
            player: *const Player,

            pub fn next(it: *Iterator) ?Equipment.KeyValue {
                if (it.player.storage.equipment.count == it.index) return null;
                defer it.index += 1;

                return it.player.equipmentAtIndex(it.index);
            }
        };
    };
};

pub const ControlGuiseAvatar = enum(u32) {
    wise = 2011,
    belle = 2021,
    _,
};

pub const MainCitySection = Storage.MainCity.Section; // TODO: maybe move the definition here?

pub const Time = struct {
    day: Day,
    period: Period,

    pub const Day = enum(u3) {
        sunday = 0,
        monday = 1,
        tuesday = 2,
        wednesday = 3,
        thursday = 4,
        friday = 5,
        saturday = 6,

        pub const Int = @typeInfo(@This()).@"enum".tag_type;

        pub fn fromInt(day_int_unwrapped: u32) Day {
            return @fromBackingInt(@intCast(day_int_unwrapped % 7));
        }

        pub fn next(day: Day) Day {
            return .fromInt(@backingInt(day) + 1);
        }
    };

    pub fn fastForwardToPeriod(time: *Time, new_period: Period) bool {
        if (time.period == new_period) return false;

        if (@backingInt(new_period) < @backingInt(time.period)) {
            time.day = time.day.next();
        }

        time.period = new_period;
        return true;
    }

    pub const Period = enum(u2) {
        morning = 0,
        afternoon = 1,
        evening = 2,
        night = 3,

        pub const Int = @typeInfo(@This()).@"enum".tag_type;

        const variants_count = 4;
        const minutes_in_day: u16 = 24 * 60;
        const minutes_in_period: u16 = minutes_in_day / variants_count;

        pub fn minutes(period: Period) u16 {
            const period_int: u16 = @backingInt(period);
            return (period_int + 1) * minutes_in_period;
        }
    };
};

pub const BigSceneTeam = struct {
    lineup_avatar_list: [lineup_avatar_max]?u32,

    pub const lineup_avatar_max = Storage.BigScene.lineup_avatar_count;

    pub const empty: BigSceneTeam = .{
        .lineup_avatar_list = @splat(null),
    };

    pub const AddAvatarError = error{ NoSpaceLeft, DuplicatedId };

    pub fn addAvatarId(team: *BigSceneTeam, avatar_id: u32) AddAvatarError!void {
        for (&team.lineup_avatar_list) |*avatar_id_maybe| {
            if (avatar_id_maybe.*) |existing_avatar_id| {
                if (existing_avatar_id == avatar_id)
                    return error.DuplicatedId;
            } else {
                avatar_id_maybe.* = avatar_id;
                break;
            }
        } else return error.NoSpaceLeft;
    }

    pub fn containsAvatarId(team: *const BigSceneTeam, avatar_id: u32) bool {
        for (&team.lineup_avatar_list) |avatar_id_maybe| {
            if (avatar_id == avatar_id_maybe) return true;
        }

        return false;
    }
};

fn avatarAtIndex(player: *const Player, index: u32) Avatar {
    const storage_avatar = player.storage.avatars.getPtr(index);

    var dressed_equipment: Avatar.DressedEquipment = .empty;
    inline for (std.enums.values(Equipment.Type), 0..) |equipment_type, type_index| {
        if (storage_avatar.dressed_equipment[type_index].unwrap()) |uid|
            dressed_equipment.put(equipment_type, @backingInt(uid));
    }

    return .{
        .id = @backingInt(storage_avatar.id.*),
        .level = storage_avatar.bits.level_up.getLevel(),
        .rank = storage_avatar.bits.level_up.getRank(),
        .unlocked_talent_num = storage_avatar.bits.mindscape.unlocked,
        .mindscape_tab = .{ .switches = storage_avatar.bits.mindscape.tab.toSwitches() },
        .favorite = storage_avatar.bits.flags.favorite,
        .weapon_show = switch (storage_avatar.bits.show_weapon_status) {
            .locked => .locked,
            .unlocked_disabled => .unlocked_show,
            .unlocked_enabled => .unlocked_hidden,
        },
        .weapon_uid_maybe = if (storage_avatar.weapon_uid_maybe.unwrap()) |uid|
            @backingInt(uid)
        else
            null,
        .dressed_equipment = dressed_equipment,
        .awake_index_maybe = storage_avatar.bits.awake.unwrap(),
        .awake_enabled = storage_avatar.bits.awake_enabled,
        .skin_id_maybe = switch (storage_avatar.bits.dressed_skin_id) {
            0 => null,
            else => |id| id,
        },
        .form_id_maybe = switch (storage_avatar.bits.form_index) {
            0 => null,
            else => |form_index| @backingInt(storage_avatar.id.*) + form_index,
        },
    };
}

fn weaponAtIndex(player: *const Player, index: u32) Weapon.KeyValue {
    const storage_kv = player.storage.weapons.getPtr(index);

    return .{
        .uid = @backingInt(storage_kv.uid.*),
        .weapon = .{
            .id = @backingInt(storage_kv.weapon.id),
            .refine = @backingInt(storage_kv.weapon.refine),
        },
    };
}

fn equipmentAtIndex(player: *const Player, index: u32) Equipment.KeyValue {
    const storage_kv = player.storage.equipment.getPtr(index);

    var sub_properties: [4]?Equipment.Property = undefined;
    for (&sub_properties, &storage_kv.equipment.sub_properties) |*sp, *sp_storage|
        sp.* = .fromStorageOptional(sp_storage);

    return .{
        .uid = @backingInt(storage_kv.uid.*),
        .equipment = .{
            .id = @backingInt(storage_kv.equipment.id),
            .main_property = .fromStorage(&storage_kv.equipment.main_property),
            .sub_properties = sub_properties,
        },
    };
}

const main_avatar_male: u32 = 2011;
const main_avatar_female: u32 = 2021;

pub fn isMainAvatar(avatar_id: u32) bool {
    return avatar_id == main_avatar_male or avatar_id == main_avatar_female;
}

pub fn avatars(player: *const Player) Avatar.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn weapons(player: *const Player) Weapon.KeyValue.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn equipment(player: *const Player) Equipment.KeyValue.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn hasAvatarWithId(player: *const Player, id_int: u32) bool {
    const id = Storage.Avatar.Id.fromInt(id_int) orelse return false;
    return player.storage.getAvatarIndexById(id) != null;
}

pub fn getAvatarById(player: *const Player, id_int: u32) ?Avatar {
    const id = Storage.Avatar.Id.fromInt(id_int) orelse return null;
    const index = player.storage.getAvatarIndexById(id) orelse return null;
    return player.avatarAtIndex(index);
}

pub fn getAvatarWithWeaponUid(player: *const Player, uid_int: u32) ?Avatar {
    const uid: Storage.Weapon.Uid = .fromInt(uid_int);
    const index = player.storage.getAvatarIndexByWeaponUid(uid) orelse return null;
    return player.avatarAtIndex(index);
}

pub const AvatarWithEquipment = struct {
    equipment_type: Equipment.Type,
    avatar: Avatar,
};

pub fn getAvatarWithEquipmentUid(player: *const Player, uid_int: u32) ?AvatarWithEquipment {
    const uid: Storage.Equipment.Uid = .fromInt(uid_int);
    const result = player.storage.getAvatarIndexByEquipmentUid(uid) orelse return null;

    return .{
        .equipment_type = @fromBackingInt(@intCast(result.equipment_slot_index + 1)),
        .avatar = player.avatarAtIndex(result.avatar_index),
    };
}

pub fn updateAvatar(player: *Player, avatar: Avatar) void {
    const avatar_index = player.storage.getAvatarIndexById(@fromBackingInt(avatar.id)).?;
    player.updateAvatarAtIndex(avatar_index, avatar);
    player.appendAvatarToSync(avatar);
}

pub fn hasWeaponWithUid(player: *Player, uid_int: u32) bool {
    const uid: Storage.Weapon.Uid = @fromBackingInt(uid_int);
    return player.storage.getWeaponIndexByUid(uid) != null;
}

pub fn getWeaponByUid(player: *Player, uid_int: u32) ?Weapon {
    const uid: Storage.Weapon.Uid = @fromBackingInt(uid_int);
    const weapon_index = player.storage.getWeaponIndexByUid(uid) orelse return null;

    return player.weaponAtIndex(weapon_index).weapon;
}

pub fn hasEquipmentWithUid(player: *Player, uid_int: u32) bool {
    const uid: Storage.Equipment.Uid = @fromBackingInt(uid_int);
    return player.storage.getEquipmentIndexByUid(uid) != null;
}

pub fn getEquipmentByUid(player: *Player, uid_int: u32) ?Equipment {
    const uid: Storage.Equipment.Uid = @fromBackingInt(uid_int);
    const equipment_index = player.storage.getEquipmentIndexByUid(uid) orelse return null;

    return player.equipmentAtIndex(equipment_index).equipment;
}

fn updateAvatarAtIndex(player: *Player, avatar_index: u32, avatar: Avatar) void {
    player.needs_save = true;

    const storage_avatar = player.storage.avatars.getPtr(avatar_index);
    storage_avatar.bits.* = .{
        .level_up = Storage.Avatar.LevelUp.fromRankAndLevel(avatar.rank, avatar.level).?,
        .flags = .{ .favorite = avatar.favorite },
        .mindscape = .{
            .unlocked = @intCast(avatar.unlocked_talent_num),
            .tab = Storage.Avatar.Mindscape.Tab.fromSwitches(avatar.mindscape_tab.switches).?,
        },
        .show_weapon_status = switch (avatar.weapon_show) {
            .locked => .locked,
            .unlocked_show => .unlocked_enabled,
            .unlocked_hidden => .unlocked_disabled,
        },
        .awake = if (avatar.awake_index_maybe) |index| @fromBackingInt(@intCast(index)) else .none,
        .awake_enabled = avatar.awake_enabled,
        .dressed_skin_id = if (avatar.skin_id_maybe) |skin_id| skin_id: {
            assert(skin_id != 0); // use `null` instead
            break :skin_id skin_id;
        } else 0,
        .form_index = if (avatar.form_id_maybe) |form_id| form_index: {
            break :form_index @intCast(form_id - avatar.id);
        } else 0,
    };

    storage_avatar.weapon_uid_maybe.* =
        if (avatar.weapon_uid_maybe) |uid| .wrap(.fromInt(uid)) else .none;

    const dressed_equipment_storage = storage_avatar.dressed_equipment;
    for (std.enums.values(Equipment.Type)) |equipment_type| {
        const equipment_index = @backingInt(equipment_type) - 1;

        if (avatar.dressed_equipment.get(equipment_type)) |uid| {
            dressed_equipment_storage[equipment_index] = .wrap(.fromInt(uid));
        } else {
            dressed_equipment_storage[equipment_index] = .none;
        }
    }
}

pub fn updateControlGuiseAvatar(player: *Player, guise: ControlGuiseAvatar) void {
    player.needs_save = true;
    player.storage.role.control_guise_avatar = @fromBackingInt(@backingInt(guise));

    player.sync.needs_player_sync_notify = true;
    player.sync.control_guise_avatar_changed = true;
}

pub fn enterMainCitySection(player: *Player, section: MainCitySection) void {
    player.needs_save = true;
    player.sync.scene.reload_hall_scene = true;
    player.temp.view_objects = null;

    player.storage.big_scene.cur_floor_id = .none;
    player.storage.main_city.section = section;
}

pub fn enterLastScene(player: *Player) void {
    if (player.isInBigScene()) {
        player.sync.scene.reload_big_scene_floor = true;
    } else {
        player.sync.scene.reload_hall_scene = true;
    }
}

pub fn enterBigSceneFloor(player: *Player, options: struct {
    floor_id: u32,
    position: [3]i32,
    rotation: [3]i32,
}) void {
    player.needs_save = true;
    player.sync.scene.reload_big_scene_floor = true;
    player.temp.view_objects = null;

    player.storage.big_scene.cur_floor_id = .wrap(options.floor_id);
    player.storage.big_scene.position = options.position;
    player.storage.big_scene.rotation = options.rotation;
}

pub const RollbackPointOptions = struct {
    position: [3]i32,
    rotation: [3]i32,
};

pub fn updateRollbackPoint(player: *Player, options: RollbackPointOptions) void {
    player.needs_save = true;
    player.storage.big_scene.position = options.position;
    player.storage.big_scene.rotation = options.rotation;
}

/// Must be called when `EnterFloorDoneCsReq` is received.
///
/// Returns `true` on success.
/// Returns `false` if logic was already started or the player
/// is not on big scene in the first place.
pub fn startBigSceneLogic(player: *Player) bool {
    if (player.temp.view_objects != null) return false; // already started.
    player.sync.scene.big_scene_logic_started = true;

    const floor_id = player.storage.big_scene.cur_floor_id.unwrap() orelse return false;
    const floor = assets.Floor.table.get(floor_id).?;

    player.temp.view_objects = @as(Temporaries.ViewObjects, undefined);
    player.temp.view_objects.?.init(floor.group_id_list);

    player.updateViewObjectGroups(&player.temp.view_objects.?, .{
        .floor = &floor,
        .position = player.storage.big_scene.position,
    });
    return true;
}

pub fn updateBigScenePosition(player: *Player, new_position: [3]i32) bool {
    const view_objects = &(player.temp.view_objects orelse return false);

    const floor_id = player.storage.big_scene.cur_floor_id.unwrap() orelse return false;
    const floor = assets.Floor.table.get(floor_id).?;

    player.updateViewObjectGroups(view_objects, .{
        .floor = &floor,
        .position = new_position,
    });

    return true;
}

const ViewObjectZone = struct {
    floor: *const assets.Floor,
    position: [3]i32,
};

fn updateViewObjectGroups(
    player: *Player,
    vo: *Temporaries.ViewObjects,
    zone: ViewObjectZone,
) void {
    _ = player;

    const position_x = zone.position[0];
    const position_y = zone.position[1];
    const position_z = zone.position[2];

    var inactive_groups = vo.groups.inactive();
    while (inactive_groups.next()) |group_id| {
        const group = assets.Group.table.getGroupMetadata(group_id).?;
        if (group.vo_group_type == 1 or group.vo_group_type == 2) {
            if (group.battle_region_areas.len == 0) {
                inactive_groups.activate();
                continue;
            }

            for (group.battle_region_areas) |battle_region_area| {
                if (position_y - battle_region_area.origin_pos.y <= battle_region_area.height_y and
                    @abs(battle_region_area.origin_pos.z - position_z) <= 4_000 and
                    @abs(battle_region_area.origin_pos.x - position_x) <= 4_000)
                {
                    inactive_groups.activate();
                    continue;
                }
            }
        }
    }
}

pub fn getMasterViewObjectEntityId(player: *Player) ?Temporaries.ViewObjects.EntityId {
    if (player.temp.view_objects) |*vo|
        return vo.master_entity_id;

    return null;
}

pub fn updateMainCityTime(player: *Player, time: Time) void {
    player.needs_save = true;
    player.storage.time = .{
        .day = @backingInt(time.day),
        .period = @backingInt(time.period),
    };

    if (player.isInHall()) {
        player.sync.scene.time_modified = true;
    } else if (player.isInBigScene()) {
        player.sync.scene.reload_big_scene_floor = true;
    } else unreachable;
}

pub fn getMainCityTime(player: *const Player) Time {
    return .{
        .day = @fromBackingInt(player.storage.time.day),
        .period = @fromBackingInt(player.storage.time.period),
    };
}

pub fn getControlGuiseAvatarId(player: *Player) u32 {
    const guise = player.storage.role.control_guise_avatar;
    const avatar_id = @backingInt(guise.toAvatarId() orelse return @backingInt(guise));
    const avatar = player.getAvatarById(avatar_id) orelse return avatar_id;

    return avatar.form_id_maybe orelse avatar_id;
}

pub fn getControlBigSceneAvatarId(player: *const Player) u32 {
    if (player.storage.big_scene.lineup_avatars[0].unwrap()) |avatar_id|
        return avatar_id;

    return 1011;
}

pub fn isInHall(player: *const Player) bool {
    return !player.isInBigScene();
}

pub fn isInBigScene(player: *const Player) bool {
    return player.storage.big_scene.cur_floor_id != .none;
}

pub fn updateKeyboardKeymap(
    player: *Player,
    keymap: Player.Storage.SystemSettings.KeyboardKeymap,
) void {
    player.needs_save = true;
    player.storage.system_settings.keyboard_keymap = keymap;
}

pub fn updateMouseKeymap(
    player: *Player,
    keymap: Player.Storage.SystemSettings.MouseKeymap,
) void {
    player.needs_save = true;
    player.storage.system_settings.mouse_keymap = keymap;
}

fn appendAvatarToSync(player: *Player, avatar: Avatar) void {
    player.sync.needs_player_sync_notify = true;
    pack.avatarInfo(player.sync.avatar_list.addOneAssumeCapacity(), avatar);

    if (avatar.id == @backingInt(player.storage.role.control_guise_avatar))
        player.sync.control_guise_avatar_changed = true;
}

pub fn getBattleAvatarInitById(player: *Player, avatar_id: u32) ?battle.AvatarInit {
    var avatar = player.getAvatarById(avatar_id) orelse return null;

    var equipment_list: [6]?Player.Equipment = @splat(null);
    var equipment_list_i: usize = 0;
    var dressed_equipment = avatar.dressed_equipment.iterator();
    while (dressed_equipment.next()) |kv| {
        defer equipment_list_i += 1;
        equipment_list[equipment_list_i] = player.getEquipmentByUid(kv.value.*).?;
    }

    return .{
        .avatar = avatar,
        .weapon_maybe = if (avatar.weapon_uid_maybe) |weapon_uid|
            player.getWeaponByUid(weapon_uid)
        else
            null,
        .equipment = equipment_list,
    };
}

pub fn getBigSceneTeam(player: *Player) BigSceneTeam {
    var team: BigSceneTeam = .{
        .lineup_avatar_list = @splat(null),
    };

    for (&team.lineup_avatar_list, player.storage.big_scene.lineup_avatars) |*out, avatar_maybe| {
        out.* = avatar_maybe.unwrap();
    }

    return team;
}

pub fn replaceBigSceneTeam(player: *Player, new_team: BigSceneTeam) void {
    player.needs_save = true;
    player.sync.needs_player_sync_notify = true;
    player.sync.big_scene_team_replaced = .{ .prev = player.getBigSceneTeam() };

    for (
        &player.storage.big_scene.lineup_avatars,
        &new_team.lineup_avatar_list,
    ) |*storage, avatar_id_maybe| {
        storage.* = if (avatar_id_maybe) |avatar_id| .wrap(avatar_id) else .none;
    }
}

pub fn buildPlayerSyncScNotify(player: *Player) ?gen.PlayerSyncScNotify {
    if (!player.sync.needs_player_sync_notify) return null;

    var notify: gen.PlayerSyncScNotify = .{ .misc = .{} };

    if (features.avatar_sync) {
        notify.avatar = .{ .avatar_list = player.sync.avatar_list.items(.avatar_info) };
    }

    const self_basic_info_needs_sync = player.sync.control_guise_avatar_changed;
    if (self_basic_info_needs_sync) {
        notify.self_basic_info = pack.selfBasicInfo(player);
    }

    const accessory_data_needs_sync = player.sync.control_guise_avatar_changed;
    if (accessory_data_needs_sync) {
        const control_guise_avatar_base = player.storage.role.control_guise_avatar;

        const guise_skin_id = if (control_guise_avatar_base.toAvatarId()) |avatar_id| skin: {
            const avatar = player.getAvatarById(@backingInt(avatar_id)).?;
            break :skin avatar.skin_id_maybe orelse 0;
        } else 0;

        notify.misc.?.player_accessory = .{
            .control_guise_avatar_id = player.getControlGuiseAvatarId(),
            .control_guise_avatar_skin_id = guise_skin_id,
        };
    }

    if (player.sync.big_scene_team_replaced) |team_replaced| big_scene_sync: {
        if (!features.big_scene_sync) break :big_scene_sync;

        const prev_team = team_replaced.prev;
        const new_team = player.getBigSceneTeam();

        var scene_avatar_list: ArrayList(gen.BigSceneAvatarInfo) =
            .initBuffer(&player.sync.buffers.big_scene_avatar_minimal);

        for (prev_team.lineup_avatar_list) |avatar_id_maybe| {
            const avatar_id = avatar_id_maybe orelse continue;

            pack.bigSceneAvatarInfoMinimal(scene_avatar_list.addOneAssumeCapacity(), .{
                .avatar_id = avatar_id,
                .hp_percentage = 100,
                .operation = .REPLACE_TEAM,
            });
        }

        for (new_team.lineup_avatar_list) |avatar_id_maybe| {
            const avatar_id = avatar_id_maybe orelse continue;
            if (!prev_team.containsAvatarId(avatar_id)) {
                pack.bigSceneAvatarInfoMinimal(scene_avatar_list.addOneAssumeCapacity(), .{
                    .avatar_id = avatar_id,
                    .hp_percentage = 100,
                    .operation = .REPLACE_TEAM,
                });
            }

            const avatar_init = player.getBattleAvatarInitById(avatar_id).?;

            var property_map: battle.Property.Map = .init;
            battle.makeAvatarProperties(&property_map, avatar_init);

            pack.bigSceneAvatarInfo(player.sync.buffers.big_scene_avatar_team.addOneAssumeCapacity(), .{
                .avatar_id = avatar_id,
                .hp_percentage = 100,
                .operation = .NONE,
                .property_map = &property_map,
            });
        }

        notify.big_scene = .{
            .scene_avatar_list = scene_avatar_list.items,
            .cur_scene_avatar_list = player.sync.buffers.big_scene_avatar_team.items(.info),
            .is_team_replaced = true,
        };
    }

    return notify;
}

pub fn buildEnterSceneScNotify(player: *Player) ?gen.EnterSceneScNotify {
    if (!player.sync.scene.reload_hall_scene) return null;

    return .{
        .scene = pack.sceneDataForHall(.{
            .main_city = &player.storage.main_city,
            .role = &player.storage.role,
            .time = player.getMainCityTime(),
        }, &player.sync.scene.hall_buffer),
    };
}

pub fn buildHallRefresh(player: *Player) ?gen.HallRefreshScNotify {
    if (player.sync.scene.reload_hall_scene) return null; // full EnterSceneScNotify is pending anyway

    const needs_hall_refresh = player.sync.scene.time_modified;
    if (!needs_hall_refresh) return null;

    var refresh_notify = pack.hall(gen.HallRefreshScNotify, .{
        .main_city = &player.storage.main_city,
        .role = &player.storage.role,
        .time = player.getMainCityTime(),
    }, &player.sync.scene.hall_buffer);
    refresh_notify.force_refresh = true;

    return refresh_notify;
}

pub fn buildEnterFloorScNotify(player: *Player) ?gen.EnterFloorScNotify {
    if (!player.sync.scene.reload_big_scene_floor) return null;

    const floor_id = player.storage.big_scene.cur_floor_id.unwrap().?;
    const pos = player.storage.big_scene.position;
    const rot = player.storage.big_scene.rotation;

    const floor = assets.Floor.table.get(floor_id).?;

    const time = player.getMainCityTime();

    return .{
        .pos = .{ .x = pos[0], .y = pos[1], .z = pos[2] },
        .floor_position = .{
            .player_position = .{ .x = pos[0], .y = pos[1], .z = pos[2] },
            .player_rotation = .{ .x = rot[0], .y = rot[1], .z = rot[2] },
        },
        .rollback_point = .{
            .position = .{ .x = pos[0], .y = pos[1], .z = pos[2] },
            .rotation = .{ .x = rot[0], .y = rot[1], .z = rot[2] },
        },
        .scene_id = floor.scene_config_id,
        .floor_id = floor_id,
        .day_of_week = @backingInt(time.day),
        .time_in_minutes = time.period.minutes(),
        .control_entity = .{
            .position = .{
                .x = pos[0],
                .y = pos[1],
                .z = pos[2],
            },
            .rotation = .{},
            .entity = .{ .Avatar = .{
                .avatar_id = @intCast(player.getControlBigSceneAvatarId()),
            } },
        },
    };
}

pub fn notifyViewObjects(
    player: *Player,
    sink: *remielle.session.Sink,
) !void {
    const view_objects = &(player.temp.view_objects orelse return);

    if (player.sync.scene.big_scene_logic_started) {
        try player.notifyMasterEntityAppearance(sink);
    }

    const group_id_list = view_objects.groups.flushGroupOrders();
    if (group_id_list.len != 0) {
        try notifyGroupMemberCreation(sink, group_id_list);
        try notifyGroupOrders(sink, group_id_list);
        try notifyGroupEntitiesAppearance(view_objects, sink, group_id_list);
    }
}

const entity_count_max =
    assets.Group.table.gadget_ids.len +
    assets.Group.table.monster_ids.len;

fn notifyGroupMemberCreation(
    sink: *remielle.session.Sink,
    group_id_list: []const u32,
) !void {
    var group_member_buffer: [entity_count_max]gen.GroupMemberId = undefined;
    var group_member_list: ArrayList(gen.GroupMemberId) = .initBuffer(&group_member_buffer);

    for (group_id_list) |group_id| {
        const group = assets.Group.table.getGroupById(group_id).?;
        for (group.configIdVec()) |config_ids| {
            for (config_ids) |config_id| {
                group_member_list.appendAssumeCapacity(.{
                    .group_id = group_id,
                    .config_id = config_id,
                });
            }
        }
    }

    try sink.notify(gen.GroupMemberCreateScNotify, &.{
        .group_member_list = group_member_list.items,
    });
}

fn notifyGroupOrders(
    sink: *remielle.session.Sink,
    group_id_list: []const u32,
) !void {
    for (group_id_list) |group_id| {
        var member_config_id_buffer: [entity_count_max]u32 = undefined;
        var member_config_id_list: ArrayList(u32) = .initBuffer(&member_config_id_buffer);
        const group = assets.Group.table.getGroupById(group_id).?;

        for (group.configIdVec()) |config_ids| {
            for (config_ids) |config_id| {
                member_config_id_list.appendAssumeCapacity(config_id);
            }
        }

        try sink.notify(gen.GroupOrderReadyScNotify, &.{ .group_info = .{
            .group_id = group_id,
            .reason = .{ .group_order_reason = @fromBackingInt(1) },
            .member_config_id_list = member_config_id_list.items,
        } });
    }
}

fn notifyMasterEntityAppearance(player: *Player, sink: *remielle.session.Sink) !void {
    const avatar_id = player.getControlBigSceneAvatarId();
    const entity_id = player.temp.view_objects.?.master_entity_id;
    const position = player.storage.big_scene.position;

    try sink.notify(gen.SceneEntityAppearScNotify, &.{
        .param = 0,
        .appear_type = @fromBackingInt(1),
        .entity_list = &.{.{
            .entity_id = entity_id.toInt(),
            .position = .{
                .x = position[0],
                .y = position[1],
                .z = position[2],
            },
            .rotation = .{},
            .entity = .{ .Avatar = .{
                .avatar_id = @intCast(avatar_id),
            } },
        }},
    });
}

const EntityBatch = struct {
    sink: *remielle.session.Sink,
    buffer: []gen.SceneEntityInfo,
    count: usize,

    fn init(sink: *remielle.session.Sink, buffer: []gen.SceneEntityInfo) EntityBatch {
        return .{
            .sink = sink,
            .buffer = buffer,
            .count = 0,
        };
    }

    fn add(batch: *EntityBatch, info: gen.SceneEntityInfo) !void {
        if (batch.count == batch.buffer.len) try batch.send();

        defer batch.count += 1;
        batch.buffer[batch.count] = info;
    }

    fn send(batch: *EntityBatch) !void {
        if (batch.count == 0) return;
        defer batch.count = 0;

        return batch.sink.notify(gen.SceneEntityAppearScNotify, &.{
            .appear_type = @fromBackingInt(1),
            .entity_list = batch.buffer[0..batch.count],
            .param = 0,
        });
    }
};

fn notifyGroupEntitiesAppearance(
    vo: *Temporaries.ViewObjects,
    sink: *remielle.session.Sink,
    group_id_list: []const u32,
) !void {
    var buffer: [128]gen.SceneEntityInfo = undefined;
    var batch: EntityBatch = .init(sink, &buffer);

    for (group_id_list) |group_id| {
        const group = assets.Group.table.getGroupById(group_id).?;
        for (
            group.gadget_config_ids,
            group.gadget_ids,
            group.gadget_positions,
        ) |config_id, gadget_id, position| {
            const entity_id = vo.nextEntityId(.gadget);

            try batch.add(.{
                .entity_id = entity_id.toInt(),
                .group_id = group_id,
                .config_id = config_id,
                .position = .{
                    .x = position.x,
                    .y = position.y,
                    .z = position.z,
                },
                .rotation = .{ .y = position.euler_y },
                .member_variables = &.{
                    .{ .key = "OpenType", .value = 0 },
                },
                .entity = .{ .Gadget = .{
                    .gadget_id = gadget_id,
                } },
            });
        }

        for (
            group.monster_config_ids,
            group.monster_ids,
            group.monster_positions,
        ) |config_id, monster_id, position| {
            const entity_id = vo.nextEntityId(.monster);

            try batch.add(.{
                .entity_id = entity_id.toInt(),
                .group_id = group_id,
                .config_id = config_id,
                .position = .{
                    .x = position.x,
                    .y = position.y,
                    .z = position.z,
                },
                .rotation = .{ .y = position.euler_y },
                .entity = .{ .Monster = .{
                    .monster_id = monster_id,
                } },
            });
        }
    }

    try batch.send();
}
