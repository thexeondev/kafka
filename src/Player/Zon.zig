//! This is a user-facing format and it's designed for convenience rather than efficiency.

const Zon = @This();

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const remielle = @import("../remielle.zig");
const client = remielle.client;
const Player = remielle.Player;
const templates = remielle.templates;
const Storage = remielle.Player.Storage;

role: Role,
main_city: MainCity,
time: Time,
keymap: Keymap,
avatars: []Avatar,
weapons_undressed: []Weapon,
equipment_undressed: []Equipment,

pub const NameMap = struct {
    avatar_id_by_name: std.array_hash_map.String(Storage.Avatar.Id),
    avatar_name_by_id: std.array_hash_map.Auto(Storage.Avatar.Id, []const u8),
    weapon_id_by_name: std.array_hash_map.String(Storage.Weapon.Id),
    weapon_name_by_id: std.array_hash_map.Auto(Storage.Weapon.Id, []const u8),
    equipment_id_by_name_rarity_s: std.array_hash_map.String(u32),
    equipment_name_by_id_rarity_s: std.array_hash_map.Auto(u32, []const u8),
    section_id_by_name: std.array_hash_map.String(u32),
    section_name_by_id: std.array_hash_map.Auto(u32, []const u8),
    avatar_form_id_by_name: std.array_hash_map.String(u32),
    avatar_form_name_by_id: std.array_hash_map.Auto(u32, []const u8),

    pub fn init(arena: Allocator, text_map: *const templates.Text.Map) Allocator.Error!NameMap {
        var avatar_id_by_name: std.array_hash_map.String(Storage.Avatar.Id) = .empty;
        try avatar_id_by_name.ensureTotalCapacity(arena, templates.AvatarBase.table.count);
        var avatar_name_by_id: std.array_hash_map.Auto(Storage.Avatar.Id, []const u8) = .empty;
        try avatar_name_by_id.ensureTotalCapacity(arena, templates.AvatarBase.table.count);

        for (
            templates.AvatarBase.table.items(.id),
            templates.AvatarBase.table.items(.code_name),
        ) |id_int, code_name| {
            const id = Storage.Avatar.Id.fromInt(id_int) orelse continue;

            const code_name_slice = templates.AvatarBase.table.getString(code_name);
            const code_name_text = text_map.get(code_name_slice) orelse code_name_slice;

            avatar_id_by_name.putAssumeCapacityNoClobber(code_name_text, id);
            avatar_name_by_id.putAssumeCapacityNoClobber(id, code_name_text);
        }

        var weapon_id_by_name: std.array_hash_map.String(Storage.Weapon.Id) = .empty;
        try weapon_id_by_name.ensureTotalCapacity(arena, templates.Weapon.table.count);
        var weapon_name_by_id: std.array_hash_map.Auto(Storage.Weapon.Id, []const u8) = .empty;
        try weapon_name_by_id.ensureTotalCapacity(arena, templates.Weapon.table.count);

        for (
            templates.Weapon.table.items(.id),
            templates.Weapon.table.items(.weapon_name),
        ) |id_int, weapon_name| {
            const id = Storage.Weapon.Id.fromInt(id_int) orelse continue;

            const weapon_name_unformatted = templates.Weapon.table.getString(weapon_name);
            const weapon_name_slice = try arena.print("Item_{s}_Name", .{weapon_name_unformatted});
            const weapon_name_text = text_map.get(weapon_name_slice) orelse weapon_name_slice;

            weapon_id_by_name.putAssumeCapacityNoClobber(weapon_name_text, id);
            weapon_name_by_id.putAssumeCapacityNoClobber(id, weapon_name_text);
        }

        var equipment_id_by_name_rarity_s: std.array_hash_map.String(u32) = .empty;
        try equipment_id_by_name_rarity_s.ensureTotalCapacity(arena, templates.Equipment.table.count);
        var equipment_name_by_id_rarity_s: std.array_hash_map.Auto(u32, []const u8) = .empty;
        try equipment_name_by_id_rarity_s.ensureTotalCapacity(arena, templates.Equipment.table.count);

        for (templates.Equipment.table.items(.id)) |id_int| {
            const rarity: Equipment.Id.Rarity = @fromBackingInt((id_int / 10) % 10);
            if (rarity != .s) continue;

            const equipment_name_slice = try arena.print("Item_Equipment_{d}_name", .{id_int});
            const equipment_name_text = text_map.get(equipment_name_slice) orelse equipment_name_slice;

            equipment_id_by_name_rarity_s.putAssumeCapacityNoClobber(equipment_name_text, id_int);
            equipment_name_by_id_rarity_s.putAssumeCapacityNoClobber(id_int, equipment_name_text);
        }

        var section_id_by_name: std.array_hash_map.String(u32) = .empty;
        try section_id_by_name.ensureTotalCapacity(arena, templates.SectionConfig.table.count);
        var section_name_by_id: std.array_hash_map.Auto(u32, []const u8) = .empty;
        try section_name_by_id.ensureTotalCapacity(arena, templates.SectionConfig.table.count);

        for (
            templates.SectionConfig.table.items(.id),
            templates.SectionConfig.table.items(.display_name),
        ) |id, display_name| {
            const display_name_slice = templates.SectionConfig.table.getString(display_name);
            if (display_name_slice.len == 0) continue;

            var display_name_text = text_map.get(display_name_slice) orelse display_name_slice;
            const get_or_put = section_id_by_name.getOrPutAssumeCapacity(display_name_text);
            if (get_or_put.found_existing) {
                display_name_text = try arena.print("Section_{d}", .{id});
                section_id_by_name.putAssumeCapacityNoClobber(display_name_text, id);
            } else {
                get_or_put.value_ptr.* = id;
            }

            section_name_by_id.putAssumeCapacityNoClobber(id, display_name_text);
        }

        var avatar_form_id_by_name: std.array_hash_map.String(u32) = .empty;
        try avatar_form_id_by_name.ensureTotalCapacity(arena, templates.AvatarForm.table.count);
        var avatar_form_name_by_id: std.array_hash_map.Auto(u32, []const u8) = .empty;
        try avatar_form_name_by_id.ensureTotalCapacity(arena, templates.AvatarForm.table.count);

        for (
            templates.AvatarForm.table.items(.id),
            templates.AvatarForm.table.items(.name),
        ) |id, name| {
            const name_slice = templates.AvatarForm.table.getString(name);
            const name_text = text_map.get(name_slice) orelse name_slice;
            avatar_form_id_by_name.putAssumeCapacityNoClobber(name_text, id);
            avatar_form_name_by_id.putAssumeCapacityNoClobber(id, name_text);
        }

        return .{
            .avatar_id_by_name = avatar_id_by_name,
            .avatar_name_by_id = avatar_name_by_id,
            .weapon_id_by_name = weapon_id_by_name,
            .weapon_name_by_id = weapon_name_by_id,
            .equipment_name_by_id_rarity_s = equipment_name_by_id_rarity_s,
            .equipment_id_by_name_rarity_s = equipment_id_by_name_rarity_s,
            .section_id_by_name = section_id_by_name,
            .section_name_by_id = section_name_by_id,
            .avatar_form_id_by_name = avatar_form_id_by_name,
            .avatar_form_name_by_id = avatar_form_name_by_id,
        };
    }

    pub fn getEquipmentIdByNameForRarity(
        name_map: *const NameMap,
        name: []const u8,
        rarity: Equipment.Id.Rarity,
    ) ?Storage.Equipment.Id {
        const id_rarity_s = name_map.equipment_id_by_name_rarity_s.get(name) orelse return null;
        const slot = id_rarity_s % 10;
        const id_int = ((id_rarity_s / 100) * 100) +
            (@backingInt(rarity) * 10) +
            slot;

        return Storage.Equipment.Id.fromInt(id_int);
    }

    pub fn getEquipmentNameAndRarityById(
        name_map: *const NameMap,
        id: Storage.Equipment.Id,
    ) Equipment.Id {
        const id_int = @backingInt(id);
        const slot = id_int % 10;
        const id_rarity_s = ((id_int / 100) * 100) +
            (@backingInt(Equipment.Id.Rarity.s) * 10) +
            slot;

        const name = name_map.equipment_name_by_id_rarity_s.get(id_rarity_s).?;
        return .{ .name = name, .rarity = @fromBackingInt((id_int / 10) % 10) };
    }
};

pub const MainCity = struct {
    section: []const u8,
};

pub const Role = struct {
    avatar: []const u8,
    control_avatar: []const u8,
    control_guise_avatar: []const u8,
};

const player_role_avatar_by_name: std.StaticStringMap(Storage.Role.Avatar) = .initComptime(.{
    .{ "Wise", .wise },
    .{ "Belle", .belle },
});

const name_by_player_role_avatar: std.EnumArray(Storage.Role.Avatar, []const u8) = .init(.{
    .wise = "Wise",
    .belle = "Belle",
});

pub const Time = struct {
    day: Player.Time.Day,
    period: Player.Time.Period,
};

pub const Avatar = struct {
    name: []const u8,
    level: u32,
    rank: u32,
    favorite: bool,
    unlocked_mindscape: u32,
    mindscape_tab_state: [Storage.Avatar.Mindscape.unlocked_max]bool,
    show_weapon_status: ShowWeaponStatus,
    weapon: ?Weapon,
    equipment: EquipmentSlots,
    awake: Awake,
    skin_id: u32,
    form: ?[]const u8,

    pub const EquipmentSlots = struct {
        @"1": ?Equipment,
        @"2": ?Equipment,
        @"3": ?Equipment,
        @"4": ?Equipment,
        @"5": ?Equipment,
        @"6": ?Equipment,
    };

    pub const ShowWeaponStatus = enum {
        locked,
        unlocked_disabled,
        unlocked_enabled,
    };

    pub const Awake = struct {
        level: u32,
        enabled: bool,
    };
};

pub const Weapon = struct {
    name: []const u8,
    refine: u32,

    fn init(data: Storage.Weapon, name_map: *const NameMap) Weapon {
        return .{
            .name = name_map.weapon_name_by_id.get(data.id).?,
            .refine = @backingInt(data.refine),
        };
    }

    fn pack(
        weapon: Weapon,
        name_map: *const NameMap,
        diag: *PackDiagnostics,
    ) PackError!Storage.Weapon {
        return .{
            .id = name_map.weapon_id_by_name.get(weapon.name) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "weapon", .name = weapon.name },
            ),
            .refine = Storage.Weapon.Refine.fromInt(weapon.refine) orelse return diag.fail(
                .weapon_refine_invalid,
                .{ .name = weapon.name, .encountered = weapon.refine },
            ),
        };
    }
};

pub const Equipment = struct {
    id: Id,
    main_property: MainProperty,
    sub_properties: SubProperties,

    pub const Id = struct {
        name: []const u8,
        rarity: Rarity,

        pub const Rarity = enum(u32) {
            s = 4,
            a = 3,
            b = 2,
        };
    };

    pub const SubProperties = struct {
        @"1": ?SubProperty,
        @"2": ?SubProperty,
        @"3": ?SubProperty,
        @"4": ?SubProperty,
    };

    pub const MainProperty = struct {
        key: []const u8,

        fn init(data: Storage.Equipment.Property) MainProperty {
            const key: Key = @fromBackingInt(@backingInt(data.key));

            return .{ .key = Key.names.get(key) };
        }

        fn pack(
            main_property: MainProperty,
            diag: *PackDiagnostics,
        ) PackError!Storage.Equipment.Property {
            const key = Key.by_name.get(main_property.key) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "main property key", .name = main_property.key },
            );

            return .{
                .key = @fromBackingInt(@backingInt(key)),
                .base = base_by_key.get(key) orelse return diag.fail(
                    .name_invalid,
                    .{ .kind = "main property key", .name = main_property.key },
                ),
                .add = 1,
            };
        }

        const base_by_key: std.EnumMap(Key, u16) = .init(.{
            .HpMax = 550,
            .HpMax_Ratio = 750,
            .Atk = 79,
            .Atk_Ratio = 750,
            .Def = 46,
            .Def_Ratio = 1200,
            .PenRatio = 600,
            .ElementAbnormalPower = 750,
            .ElementMystery = 23,
            .CritDmg = 1200,
            .Crit = 600,
            .SpRecover = 1500,
            .BreakStun = 450,
            .AddedDamageRatioElec = 750,
            .AddedDamageRatioEther = 750,
            .AddedDamageRatioFire = 750,
            .AddedDamageRatioIce = 750,
            .AddedDamageRatioPhysics = 750,
            .AddedDamageRatioWind = 750,
        });
    };

    pub const SubProperty = struct {
        key: []const u8,
        @"+": u16,

        fn init(data: Storage.Equipment.Property) SubProperty {
            const key: Key = @fromBackingInt(@backingInt(data.key));

            return .{
                .key = Key.names.get(key),
                .@"+" = data.add - 1,
            };
        }

        fn pack(
            sub_property: SubProperty,
            diag: *PackDiagnostics,
        ) PackError!Storage.Equipment.Property {
            const key = Key.by_name.get(sub_property.key) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "sub property key", .name = sub_property.key },
            );

            return .{
                .key = @fromBackingInt(@backingInt(key)),
                .base = base_by_key.get(key) orelse return diag.fail(
                    .name_invalid,
                    .{ .kind = "sub property key", .name = sub_property.key },
                ),
                .add = sub_property.@"+" + 1,
            };
        }

        const base_by_key: std.EnumMap(Key, u16) = .init(.{
            .HpMax = 112,
            .HpMax_Ratio = 300,
            .Atk = 19,
            .Atk_Ratio = 300,
            .Def = 15,
            .Def_Ratio = 480,
            .PenDelta = 9,
            .ElementMystery = 9,
            .CritDmg = 480,
            .Crit = 240,
        });
    };

    pub const Key = enum(u16) {
        HpMax = 11103,
        HpMax_Ratio = 11102,
        Atk = 12103,
        Atk_Ratio = 12102,
        Def = 13103,
        Def_Ratio = 13102,
        PenDelta = 23203,
        PenRatio = 23103,
        ElementAbnormalPower = 31402,
        ElementMystery = 31203,
        CritDmg = 21103,
        Crit = 20103,
        SpRecover = 30502,
        BreakStun = 12202,
        AddedDamageRatioElec = 31803,
        AddedDamageRatioEther = 31903,
        AddedDamageRatioFire = 31603,
        AddedDamageRatioIce = 31703,
        AddedDamageRatioPhysics = 31503,
        AddedDamageRatioWind = 32303,

        pub const by_name: std.StaticStringMap(Key) = .initComptime(&.{
            .{ "HP", .HpMax },
            .{ "Percent HP", .HpMax_Ratio },
            .{ "ATK", .Atk },
            .{ "Percent ATK", .Atk_Ratio },
            .{ "DEF", .Def },
            .{ "Percent DEF", .Def_Ratio },
            .{ "PEN", .PenDelta },
            .{ "PEN Ratio", .PenRatio },
            .{ "Anomaly Mastery", .ElementAbnormalPower },
            .{ "Anomaly Proficiency", .ElementMystery },
            .{ "CRIT DMG", .CritDmg },
            .{ "CRIT Rate", .Crit },
            .{ "Energy Regen", .SpRecover },
            .{ "Impact", .BreakStun },
            .{ "Electric DMG Bonus", .AddedDamageRatioElec },
            .{ "Ether DMG Bonus", .AddedDamageRatioEther },
            .{ "Fire DMG Bonus", .AddedDamageRatioFire },
            .{ "Ice DMG Bonus", .AddedDamageRatioIce },
            .{ "Physical DMG Bonus", .AddedDamageRatioPhysics },
            .{ "Wind DMG Bonus", .AddedDamageRatioWind },
        });

        pub const names: std.EnumArray(Key, []const u8) = .init(.{
            .HpMax = "HP",
            .HpMax_Ratio = "Percent HP",
            .Atk = "ATK",
            .Atk_Ratio = "Percent ATK",
            .Def = "DEF",
            .Def_Ratio = "Percent DEF",
            .PenDelta = "PEN",
            .PenRatio = "PEN Ratio",
            .ElementAbnormalPower = "Anomaly Mastery",
            .ElementMystery = "Anomaly Proficiency",
            .CritDmg = "CRIT DMG",
            .Crit = "CRIT Rate",
            .SpRecover = "Energy Regen",
            .BreakStun = "Impact",
            .AddedDamageRatioElec = "Electric DMG Bonus",
            .AddedDamageRatioEther = "Ether DMG Bonus",
            .AddedDamageRatioFire = "Fire DMG Bonus",
            .AddedDamageRatioIce = "Ice DMG Bonus",
            .AddedDamageRatioPhysics = "Physical DMG Bonus",
            .AddedDamageRatioWind = "Wind DMG Bonus",
        });
    };

    fn init(data: Storage.Equipment, name_map: *const NameMap) Equipment {
        return .{
            .id = name_map.getEquipmentNameAndRarityById(data.id),
            .main_property = .init(data.main_property),
            .sub_properties = .{
                .@"1" = if (data.sub_properties[0].unwrap()) |p| .init(p) else null,
                .@"2" = if (data.sub_properties[1].unwrap()) |p| .init(p) else null,
                .@"3" = if (data.sub_properties[2].unwrap()) |p| .init(p) else null,
                .@"4" = if (data.sub_properties[3].unwrap()) |p| .init(p) else null,
            },
        };
    }

    fn pack(
        equipment: Equipment,
        name_map: *const NameMap,
        diag: *PackDiagnostics,
    ) PackError!Storage.Equipment {
        return .{
            .id = name_map.getEquipmentIdByNameForRarity(
                equipment.id.name,
                equipment.id.rarity,
            ) orelse return diag.fail(
                .equipment_invalid,
                .{ .name = equipment.id.name, .rarity = equipment.id.rarity },
            ),
            .main_property = try equipment.main_property.pack(diag),
            .sub_properties = sub_properties: {
                const sub_properties_count = Storage.Equipment.Property.sub_count;
                var sub_properties: [sub_properties_count]Storage.Equipment.Property.Optional =
                    undefined;

                inline for (
                    &sub_properties,
                    @typeInfo(SubProperties).@"struct".field_names,
                ) |*sub_property_maybe, property_name| {
                    if (@field(equipment.sub_properties, property_name)) |property| {
                        sub_property_maybe.* = .wrap(try property.pack(diag));
                    } else {
                        sub_property_maybe.* = .none;
                    }
                }

                break :sub_properties sub_properties;
            },
        };
    }
};

pub const Keymap = struct {
    keyboard: []const Keyboard,
    mouse: []const Mouse,

    pub const Keyboard = struct {
        key: client.KeyboardKey,
        action: client.LogicButtonInputType,
    };

    pub const Mouse = struct {
        button: client.MouseButton,
        action: client.LogicButtonInputType,
    };
};

pub fn init(arena: Allocator, name_map: *const NameMap, player: *Storage) Allocator.Error!Zon {
    const role: Role = .{
        .avatar = name_by_player_role_avatar.get(player.role.avatar),
        .control_avatar = name_by_player_role_avatar.get(player.role.control_avatar),
        .control_guise_avatar = switch (player.role.control_guise_avatar) {
            .wise, .belle => |main| name_by_player_role_avatar.get(@fromBackingInt(@backingInt(main))),
            _ => |custom_guise| custom: {
                const custom_avatar_id = custom_guise.toAvatarId().?;
                break :custom name_map.avatar_name_by_id.get(custom_avatar_id).?;
            },
        },
    };

    const main_city: MainCity = .{
        .section = name_map.section_name_by_id.get(@backingInt(player.main_city.section)).?,
    };

    const time: Time = .{
        .day = @fromBackingInt(player.time.day),
        .period = @fromBackingInt(player.time.period),
    };

    const avatars = try arena.alloc(Avatar, player.avatars.count);

    for (
        avatars,
        player.avatars.items(.bits),
        player.avatars.items(.id),
        player.avatars.items(.weapon_uid_maybe),
        player.avatars.items(.dressed_equipment),
    ) |*avatar_zon, bits, id, weapon_uid_maybe, dressed_equipment| {
        const weapon_maybe: ?Weapon = if (weapon_uid_maybe.unwrap()) |weapon_uid| weapon: {
            const weapon_index = player.getWeaponIndexByUid(weapon_uid).?;
            break :weapon .init(player.weapons.items(.weapon)[weapon_index], name_map);
        } else null;

        var equipment: Avatar.EquipmentSlots = undefined;
        inline for (
            @typeInfo(Avatar.EquipmentSlots).@"struct".field_names,
            dressed_equipment,
        ) |slot_name, equipment_uid_maybe| {
            if (equipment_uid_maybe.unwrap()) |equipment_uid| {
                const equipment_index = player.getEquipmentIndexByUid(equipment_uid).?;
                @field(equipment, slot_name) = .init(
                    player.equipment.items(.equipment)[equipment_index],
                    name_map,
                );
            } else {
                @field(equipment, slot_name) = null;
            }
        }

        avatar_zon.* = .{
            .name = name_map.avatar_name_by_id.get(id).?,
            .level = bits.level_up.getLevel(),
            .rank = bits.level_up.getRank(),
            .favorite = bits.flags.favorite,
            .unlocked_mindscape = bits.mindscape.unlocked,
            .mindscape_tab_state = bits.mindscape.tab.toSwitches(),
            .show_weapon_status = switch (bits.show_weapon_status) {
                .locked => .locked,
                .unlocked_disabled => .unlocked_disabled,
                .unlocked_enabled => .unlocked_enabled,
            },
            .weapon = weapon_maybe,
            .equipment = equipment,
            .awake = .{
                .level = bits.awake.toIndex() orelse 0,
                .enabled = bits.awake_enabled,
            },
            .skin_id = bits.dressed_skin_id,
            .form = name_map.avatar_form_name_by_id.get(@backingInt(id) + bits.form_index) orelse none: {
                assert(bits.form_index == 0);
                break :none null;
            },
        };
    }

    var weapons: std.ArrayList(Weapon) = try .initCapacity(arena, player.weapons.count);
    for (player.weapons.items(.uid), player.weapons.items(.weapon)) |uid, weapon| {
        if (player.getAvatarIndexByWeaponUid(uid) != null)
            continue;

        weapons.appendAssumeCapacity(.init(weapon, name_map));
    }

    var equipment_list: std.ArrayList(Equipment) = try .initCapacity(arena, player.equipment.count);
    for (player.equipment.items(.uid), player.equipment.items(.equipment)) |uid, equipment| {
        if (player.getAvatarIndexByEquipmentUid(uid) != null)
            continue;

        equipment_list.appendAssumeCapacity(.init(equipment, name_map));
    }

    const keyboard_keys = try arena.alloc(
        Keymap.Keyboard,
        player.system_settings.keyboard_keymap.list.count,
    );
    for (
        keyboard_keys,
        player.system_settings.keyboard_keymap.list.items(.key),
        player.system_settings.keyboard_keymap.list.items(.input),
    ) |*keymap, key, input| {
        keymap.* = .{ .key = key, .action = input };
    }

    const mouse_buttons = try arena.alloc(
        Keymap.Mouse,
        player.system_settings.mouse_keymap.list.count,
    );
    for (
        mouse_buttons,
        player.system_settings.mouse_keymap.list.items(.key),
        player.system_settings.mouse_keymap.list.items(.input),
    ) |*keymap, key, input| {
        keymap.* = .{ .button = key, .action = input };
    }

    return .{
        .role = role,
        .main_city = main_city,
        .time = time,
        .keymap = .{
            .keyboard = keyboard_keys,
            .mouse = mouse_buttons,
        },
        .avatars = avatars,
        .weapons_undressed = weapons.items,
        .equipment_undressed = equipment_list.items,
    };
}

pub const PackDiagnostics = union(enum) {
    limit_exceeded: struct {
        name: []const u8,
        limit: usize,
    },
    name_invalid: struct {
        kind: []const u8,
        name: []const u8,
    },
    equipment_invalid: struct {
        rarity: Equipment.Id.Rarity,
        name: []const u8,
    },
    avatar_duplicated: struct {
        avatar_name: []const u8,
    },
    avatar_level_up_invalid: struct {
        avatar_name: []const u8,
        rank: u32,
        level: u32,
    },
    avatar_mindscape_invalid: struct {
        avatar_name: []const u8,
        unlocked: u32,
        tab_state: [Storage.Avatar.Mindscape.unlocked_max]bool,
    },
    weapon_refine_invalid: struct {
        name: []const u8,
        encountered: u32,
    },
    avatar_awake_level_invalid: struct {
        avatar_name: []const u8,
        level: u32,
    },
    avatar_awake_enable_invalid: struct {
        avatar_name: []const u8,
    },
    keyboard_keymap_duplicated: Keymap.Keyboard,
    mouse_keymap_duplicated: Keymap.Mouse,

    pub fn format(diag: *const PackDiagnostics, writer: *Io.Writer) Io.Writer.Error!void {
        switch (diag.*) {
            .limit_exceeded => |details| return writer.print(
                "too many {s} encountered, the limit is {d}",
                .{ details.name, details.limit },
            ),
            .name_invalid => |details| return writer.print(
                "invalid {s} name: {q}",
                .{ details.kind, details.name },
            ),
            .equipment_invalid => |details| return writer.print(
                "invalid equipment name {q} and rarity {t}",
                .{ details.name, details.rarity },
            ),
            .avatar_duplicated => |details| return writer.print(
                "duplicated avatar {q}",
                .{details.avatar_name},
            ),
            .avatar_level_up_invalid => |details| return writer.print(
                "avatar {q} has an invalid rank and level combination ({d}, {d})",
                .{ details.avatar_name, details.rank, details.level },
            ),
            .avatar_mindscape_invalid => |details| return writer.print(
                "avatar {q} has an invalid mindscape unlock and tab combination ({d}, {any})",
                .{ details.avatar_name, details.unlocked, details.tab_state },
            ),
            .weapon_refine_invalid => |details| return writer.print(
                "weapon {q} has an invalid refine value ({d}, expected {d}-{d})",
                .{
                    details.name,              details.encountered,
                    Storage.Weapon.Refine.min, Storage.Weapon.Refine.max,
                },
            ),
            .avatar_awake_level_invalid => |details| return writer.print(
                "avatar {q} has an invalid awake level ({d})",
                .{ details.avatar_name, details.level },
            ),
            .avatar_awake_enable_invalid => |details| return writer.print(
                "avatar {q} awake cannot be enabled",
                .{details.avatar_name},
            ),
            .keyboard_keymap_duplicated => |details| return writer.print(
                "duplicated keyboard keymap: {any}",
                .{details},
            ),
            .mouse_keymap_duplicated => |details| return writer.print(
                "duplicated mouse keymap: {any}",
                .{details},
            ),
        }
    }

    fn fail(
        diag: *PackDiagnostics,
        comptime cause: @EnumLiteral(),
        details: @FieldType(PackDiagnostics, @tagName(cause)),
    ) PackError {
        diag.* = @unionInit(PackDiagnostics, @tagName(cause), details);
        return error.CheckDiagnostics;
    }
};

pub const PackError = error{CheckDiagnostics};

pub fn pack(
    zon: *const Zon,
    name_map: *const NameMap,
    diag: *PackDiagnostics,
) PackError!Storage {
    const section_id_int = name_map.section_id_by_name.get(zon.main_city.section) orelse
        return diag.fail(
            .name_invalid,
            .{ .kind = "section", .name = zon.main_city.section },
        );

    var player: Storage = .{
        .avatars = .empty,
        .weapons = .empty,
        .weapon_uid_counter = 0,
        .equipment = .empty,
        .equipment_uid_counter = 0,
        .main_city = .{
            .section = @fromBackingInt(section_id_int),
        },
        .role = .{
            .avatar = player_role_avatar_by_name.get(zon.role.avatar) orelse
                return diag.fail(
                    .name_invalid,
                    .{ .kind = "role avatar", .name = zon.role.avatar },
                ),
            .control_avatar = player_role_avatar_by_name.get(zon.role.control_avatar) orelse
                return diag.fail(
                    .name_invalid,
                    .{ .kind = "role control avatar", .name = zon.role.avatar },
                ),
            .control_guise_avatar = if (player_role_avatar_by_name.get(zon.role.control_guise_avatar)) |role|
                @fromBackingInt(@backingInt(role))
            else
                @fromBackingInt(@backingInt(name_map.avatar_id_by_name.get(zon.role.control_guise_avatar) orelse
                    return diag.fail(
                        .name_invalid,
                        .{ .kind = "role control guise avatar", .name = zon.role.control_guise_avatar },
                    ))),
        },
        .time = .{
            .day = @backingInt(zon.time.day),
            .period = @backingInt(zon.time.period),
        },
        .big_scene = .{
            .cur_floor_id = .none, // TODO
            .position = @splat(0), // TODO
            .rotation = @splat(0), // TODO
            .lineup_avatars = @splat(.none), // TODO
        },
        .system_settings = .{
            .keyboard_keymap = .empty,
            .mouse_keymap = .empty,
        },
    };

    for (zon.avatars) |avatar_zon| {
        const weapon_uid_maybe: Storage.Weapon.Uid.Optional = if (avatar_zon.weapon) |weapon_zon| add: {
            const weapon = try weapon_zon.pack(name_map, diag);
            const weapon_uid = player.addWeapon(weapon) catch |err| switch (err) {
                error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                    .name = "weapons",
                    .limit = Storage.Weapon.count_max,
                }),
            };

            break :add .wrap(weapon_uid);
        } else .none;

        var dressed_equipment: [Storage.Avatar.equipment_count]Storage.Equipment.Uid.Optional =
            undefined;

        inline for (
            &dressed_equipment,
            @typeInfo(Avatar.EquipmentSlots).@"struct".field_names,
        ) |*equipment_uid_maybe, slot_name| {
            if (@field(avatar_zon.equipment, slot_name)) |equipment_zon| {
                const equipment = try equipment_zon.pack(name_map, diag);
                equipment_uid_maybe.* =
                    .wrap(player.addEquipment(equipment) catch |err| switch (err) {
                        error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                            .name = "equipment",
                            .limit = Storage.Equipment.count_max,
                        }),
                    });
            } else {
                equipment_uid_maybe.* = .none;
            }
        }

        const avatar_id = name_map.avatar_id_by_name.get(avatar_zon.name) orelse return diag.fail(
            .name_invalid,
            .{ .kind = "avatar", .name = avatar_zon.name },
        );

        if (avatar_zon.awake.enabled and avatar_zon.awake.level == 0) {
            return diag.fail(.avatar_awake_enable_invalid, .{ .avatar_name = avatar_zon.name });
        }

        if (avatar_zon.awake.level != 0 and
            templates.AvatarSpecialAwaken.getByAvatarIdAndIndex(
                @backingInt(avatar_id),
                avatar_zon.awake.level,
            ) == null)
        {
            return diag.fail(.avatar_awake_level_invalid, .{
                .avatar_name = avatar_zon.name,
                .level = avatar_zon.awake.level,
            });
        }

        const form_index: u2 = form_index: {
            const form_name = avatar_zon.form orelse break :form_index 0;
            const form_id = name_map.avatar_form_id_by_name.get(form_name) orelse
                return diag.fail(.name_invalid, .{ .name = form_name, .kind = "avatar form" });

            const form_template = templates.AvatarForm.table.getByKey(form_id).?;
            if (form_template.avatar_id != @backingInt(avatar_id))
                return diag.fail(.name_invalid, .{ .name = form_name, .kind = "avatar form" });

            break :form_index @intCast(form_id - form_template.avatar_id);
        };

        const avatar: Storage.Avatar = .{
            .id = avatar_id,
            .bits = .{
                .level_up = Storage.Avatar.LevelUp.fromRankAndLevel(
                    avatar_zon.rank,
                    avatar_zon.level,
                ) orelse return diag.fail(.avatar_level_up_invalid, .{
                    .avatar_name = avatar_zon.name,
                    .rank = avatar_zon.rank,
                    .level = avatar_zon.level,
                }),
                .mindscape = Storage.Avatar.Mindscape.fromUnlockedAndSwitches(
                    avatar_zon.unlocked_mindscape,
                    avatar_zon.mindscape_tab_state,
                ) orelse return diag.fail(
                    .avatar_mindscape_invalid,
                    .{
                        .avatar_name = avatar_zon.name,
                        .unlocked = avatar_zon.unlocked_mindscape,
                        .tab_state = avatar_zon.mindscape_tab_state,
                    },
                ),
                .show_weapon_status = switch (avatar_zon.show_weapon_status) {
                    .locked => .locked,
                    .unlocked_disabled => .unlocked_disabled,
                    .unlocked_enabled => .unlocked_enabled,
                },
                .flags = .{ .favorite = avatar_zon.favorite },
                .awake = @fromBackingInt(@intCast(avatar_zon.awake.level)),
                .awake_enabled = avatar_zon.awake.enabled,
                .dressed_skin_id = avatar_zon.skin_id,
                .form_index = form_index,
            },
            .weapon_uid_maybe = weapon_uid_maybe,
            .dressed_equipment = dressed_equipment,
        };

        const result = player.getOrAddAvatar(avatar) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "avatars",
                .limit = Storage.Avatar.count_max,
            }),
        };

        if (result.found_existing) return diag.fail(.avatar_duplicated, .{
            .avatar_name = avatar_zon.name,
        });
    }

    for (zon.weapons_undressed) |weapon_zon| {
        const weapon = try weapon_zon.pack(name_map, diag);
        _ = player.addWeapon(weapon) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "weapons",
                .limit = Storage.Weapon.count_max,
            }),
        };
    }

    for (zon.equipment_undressed) |equipment_zon| {
        const equipment = try equipment_zon.pack(name_map, diag);
        _ = player.addEquipment(equipment) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "equipment",
                .limit = Storage.Equipment.count_max,
            }),
        };
    }

    for (zon.keymap.keyboard) |keymap| {
        if (!player.system_settings.keyboard_keymap.put(keymap.key, keymap.action))
            return diag.fail(.keyboard_keymap_duplicated, keymap);
    }

    for (zon.keymap.mouse) |keymap| {
        if (!player.system_settings.mouse_keymap.put(keymap.button, keymap.action))
            return diag.fail(.mouse_keymap_duplicated, keymap);
    }

    return player;
}
