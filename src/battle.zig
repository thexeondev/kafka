const std = @import("std");

const kafka = @import("kafka.zig");
const Player = kafka.Player;
const templates = kafka.templates;
const IntMultiSet = kafka.IntMultiSet;

const rate_div = 10_000;
const rupture_weapon_type = 6;

pub const AvatarInit = struct {
    avatar: Player.Avatar,
    weapon_maybe: ?Player.Weapon,
    equipment: [6]?Player.Equipment,
};

pub fn makeAvatarProperties(
    map: *Property.Map,
    init: AvatarInit,
) void {
    const avatar: AvatarConfig = .init(&init.avatar);
    avatar.populateMap(map);

    if (init.weapon_maybe) |*player_weapon| {
        const weapon: WeaponConfig = .init(player_weapon);
        weapon.applyProperties(map);
    }

    var suit_set: IntMultiSet(u32, Player.Equipment.Type.count) = .empty;
    for (init.equipment) |player_equipment_maybe| {
        const player_equipment = player_equipment_maybe orelse continue;
        const equipment: EquipmentConfig = .init(&player_equipment);
        suit_set.putAssertCapacity(equipment.getSuitId());
        equipment.applyProperties(map);
    }

    var suits = suit_set.iterator();
    while (suits.next()) |suit| {
        const template = templates.EquipmentSuit.table.getByKey(suit.value).?;
        if (template.primary_condition > suit.times) continue;

        addProperties(map, &template.primary_suit_properties);
    }

    populateFinalProperties(map);

    applyCoreSkillSpecial(map, init.avatar.id, 6); // TODO
    if (avatar.battle.weapon_type == rupture_weapon_type) {
        map.add(.SkipDefAtk, @divFloor(map.get(.Atk) * 30, 100));
    }

    populateBattleProperties(map);
    map.add(.Hp, map.get(.HpMax));
}

// TODO: find out where this is actually configured
const core_skill_specials: []const struct { u32, Property.Index, Property.Index, *const [7]i32 } = &.{
    // Yidhari - 10% HP -> SheerForce
    .{ 1051, .SkipDefAtk, .HpMax, &@splat(10) },
    // Ben - 40-80% DEF -> ATK
    .{ 1121, .Atk, .Def, &.{ 40, 46, 52, 60, 66, 72, 80 } },
    // Yixuan - 10% HP -> SheerForce
    .{ 1371, .SkipDefAtk, .HpMax, &@splat(10) },
    // Komano Manato - 10% HP -> SheerForce
    .{ 1441, .SkipDefAtk, .HpMax, &@splat(10) },
    // BanYue - 10% HP -> SheerForce
    .{ 1471, .SkipDefAtk, .HpMax, &@splat(10) },
    // Starlight - Billy - 10% HP -> SheerForce
    .{ 1531, .SkipDefAtk, .HpMax, &@splat(10) },
    // Sunbringer - 35% CritDMG -> CritRate
    .{ 1601, .Crit, .CritDmg, &@splat(35) },
    // Claret - 35% CritDMG -> CritRate
    .{ 1611, .Crit, .CritDmg, &@splat(35) },
};

fn applyCoreSkillSpecial(map: *Property.Map, avatar_id: u32, skill_level: u32) void {
    for (core_skill_specials) |special| {
        const special_avatar_id, const bonus_prop, const scale_prop, const ratio = special;
        if (avatar_id == special_avatar_id) {
            const add = @divFloor(map.get(scale_prop) * ratio[skill_level], 100);
            map.add(bonus_prop, add);
            break;
        }
    }
}

const AvatarConfig = struct {
    data: *const Player.Avatar,
    battle: templates.AvatarBattle,
    level_advance: templates.AvatarLevelAdvance,
    passive_skill: templates.AvatarPassiveSkill,

    fn init(data: *const Player.Avatar) AvatarConfig {
        return .{
            .data = data,
            .battle = templates.AvatarBattle.table.getByKey(data.id).?,
            .level_advance = templates.AvatarLevelAdvance.getByIdAndRank(data.id, data.rank).?,
            .passive_skill = templates.AvatarPassiveSkill.getByAvatarIdAndLevel(data.id, 6).?,
        };
    }

    fn populateMap(config: *const AvatarConfig, map: *Property.Map) void {
        config.setLevelDependentProperties(map);
        config.setMiscProperties(map);

        addProperties(map, &config.passive_skill.properties);
    }

    fn setMiscProperties(config: *const AvatarConfig, map: *Property.Map) void {
        map.set(.BreakStunBase, config.battle.break_stun);
        map.set(.CritBase, config.battle.crit);
        map.set(.CritDmgBase, config.battle.crit_damage);
        map.set(.SharpCriticalDamageBase, config.battle.sharp_critical_damage);
        map.set(.SpMaxBase, config.battle.sp_bar_point);
        map.set(.SpRecoverBase, config.battle.sp_recover);
        map.set(.ElementMysteryBase, config.battle.element_mystery);
        map.set(.ElementAbnormalPowerBase, config.battle.element_abnormal_power);
        map.set(.RpMax, config.battle.rp_max);
        map.set(.RpRecoverBase, config.battle.rp_recover);
        map.set(.EpMax, config.battle.ep_max);
        map.set(.EpRecoverBase, config.battle.ep_recover);
    }

    fn setLevelDependentProperties(config: *const AvatarConfig, map: *Property.Map) void {
        map.set(
            .HpMaxBase,
            config.growProperty(config.battle.hp_max, config.battle.health_growth) +
                config.level_advance.hp_max,
        );

        map.set(
            .DefBase,
            config.growProperty(config.battle.defence, config.battle.defence_growth) +
                config.level_advance.defence,
        );

        map.set(
            .AtkBase,
            config.growProperty(config.battle.attack, config.battle.attack_growth) +
                config.level_advance.attack,
        );
    }

    fn growProperty(config: *const AvatarConfig, base: i32, growth: i32) i32 {
        const growth_float: f32 = @floatFromInt(growth);
        const level_float: f32 = @floatFromInt(config.data.level - 1);

        const add: i32 = @trunc((level_float * growth_float) / rate_div);
        return base + add;
    }
};

const WeaponConfig = struct {
    data: *const Player.Weapon,
    base: templates.Weapon,
    level: templates.WeaponLevel,
    star: templates.WeaponStar,

    pub fn init(data: *const Player.Weapon) WeaponConfig {
        return .{
            .data = data,
            .base = templates.Weapon.table.getByKey(data.id).?,
            .level = templates.WeaponLevel.getByWeaponIdAndLevel(data.id, 60).?, // TODO
            .star = templates.WeaponStar.getByWeaponIdAndStar(data.id, 5).?, // TODO
        };
    }

    pub fn applyProperties(config: *const WeaponConfig, map: *Property.Map) void {
        const level_rate: f32 = @floatFromInt(config.level.rate);
        const star_base_rate: f32 = @floatFromInt(config.star.base_rate);
        const star_rand_rate: f32 = @floatFromInt(config.star.rand_rate);

        const base_unscaled: f32 = @floatFromInt(config.base.base_property.value);
        const base: i32 = @trunc(base_unscaled * (rate_div + level_rate + star_base_rate) / rate_div);

        const rand_unscaled: f32 = @floatFromInt(config.base.rand_property.value);
        const rand: i32 = @trunc(rand_unscaled + (rand_unscaled * star_rand_rate) / rate_div);

        addProperties(map, &.{
            .{ .id = config.base.base_property.id, .value = base },
            .{ .id = config.base.rand_property.id, .value = rand },
        });
    }
};

const EquipmentConfig = struct {
    data: *const Player.Equipment,
    level: templates.EquipmentLevel,

    fn init(data: *const Player.Equipment) EquipmentConfig {
        return .{
            .data = data,
            .level = templates.EquipmentLevel.getByEquipmentIdAndLevel(data.id, 15).?, // TODO
        };
    }

    fn getSuitId(config: *const EquipmentConfig) u32 {
        return (config.data.id / 100) * 100;
    }

    fn applyProperties(config: *const EquipmentConfig, map: *Property.Map) void {
        const enhance_rate: f32 = @floatFromInt(config.level.enhance_rate);
        const main_unscaled: f32 = @floatFromInt(config.data.main_property.base);
        const main: i32 = @trunc(main_unscaled + (main_unscaled * enhance_rate / rate_div));
        addProperties(map, &.{.{ .id = config.data.main_property.key, .value = main }});

        for (config.data.sub_properties) |sub_property_maybe| {
            const sub_property = sub_property_maybe orelse continue;
            const value_unscaled: f32 = @floatFromInt(sub_property.base);
            const multiplier: f32 = @floatFromInt(sub_property.add);
            addProperties(map, &.{.{
                .id = sub_property.key,
                .value = @trunc(value_unscaled * multiplier),
            }});
        }
    }
};

fn addProperties(
    map: *Property.Map,
    add_values: []const templates.PropertyValue.Optional,
) void {
    for (add_values) |property_value_maybe| {
        const property_value = property_value_maybe.unwrap() orelse continue;
        const property: Property = @fromBackingInt(@intCast(property_value.id));
        const property_index = property.toIndex() orelse continue;

        map.add(property_index, property_value.value);
    }
}

fn populateFinalProperties(map: *Property.Map) void {
    setFinal(map, .HpMax, .HpMaxBase, .HpMaxRatio, .HpMaxDelta);
    setFinal(map, .SpMax, .SpMaxBase, .None, .SpMaxDelta);
    setFinal(map, .RpMax, .RpMaxBase, .None, .RpMaxDelta);
    setFinal(map, .EpMax, .EpMaxBase, .None, .EpMaxDelta);
    setFinal(map, .Atk, .AtkBase, .AtkRatio, .AtkDelta);
    setFinal(map, .BreakStun, .BreakStunBase, .BreakStunRatio, .BreakStunDelta);
    setFinal(map, .SkipDefAtk, .SkipDefAtkBase, .None, .SkipDefAtkDelta);
    setFinal(map, .Def, .DefBase, .DefRatio, .DefDelta);
    setFinal(map, .Crit, .CritBase, .None, .CritDelta);
    setFinal(map, .CritDmg, .CritDmgBase, .None, .CritDmgDelta);
    setFinal(map, .SharpCriticalDamage, .SharpCriticalDamageBase, .None, .SharpCriticalDamageDelta);
    setFinal(map, .Pen, .PenBase, .None, .PenDelta);
    setFinal(map, .PenValue, .PenValueBase, .None, .PenValueDelta);
    setFinal(map, .SpRecover, .SpRecoverBase, .SpRecoverRatio, .SpRecoverDelta);
    setFinal(map, .RpRecover, .RpRecoverBase, .RpRecoverRatio, .RpRecoverDelta);
    setFinal(map, .EpRecover, .EpRecoverBase, .EpRecoverRatio, .EpRecoverDelta);
    setFinal(map, .ElementMystery, .ElementMysteryBase, .None, .ElementMysteryDelta);
    setFinal(map, .ElementAbnormalPower, .ElementAbnormalPowerBase, .ElementAbnormalPowerRatio, .ElementAbnormalPowerDelta);
    setFinal(map, .AddedDamageRatio, .AddedDamageRatio1, .None, .AddedDamageRatio3);
    setFinal(map, .AddedDamageRatioPhysics, .AddedDamageRatioPhysics1, .None, .AddedDamageRatioPhysics3);
    setFinal(map, .AddedDamageRatioFire, .AddedDamageRatioFire1, .None, .AddedDamageRatioFire3);
    setFinal(map, .AddedDamageRatioIce, .AddedDamageRatioIce1, .None, .AddedDamageRatioIce3);
    setFinal(map, .AddedDamageRatioElec, .AddedDamageRatioElec1, .None, .AddedDamageRatioElec3);
    setFinal(map, .AddedDamageRatioEther, .AddedDamageRatioEther1, .None, .AddedDamageRatioEther3);
    setFinal(map, .SkipDefDamageRatio, .SkipDefDamageRatio1, .None, .SkipDefDamageRatio3);
    setFinal(map, .AddedDamageRatioWind, .AddedDamageRatioWind1, .None, .AddedDamageRatioWind3);
}

fn setFinal(
    map: *Property.Map,
    prop: Property.Index,
    base_prop: Property.Index,
    ratio_prop: Property.Index,
    delta_prop: Property.Index,
) void {
    const base = map.get(base_prop);
    const delta = map.get(delta_prop);
    const ratio: f32 = @floatFromInt(map.get(ratio_prop));

    const base_float: f32 = @floatFromInt(base);
    var base_scaled = (base_float * ratio) / rate_div;
    if (prop == .HpMax) base_scaled = @ceil(base_scaled);

    map.set(prop, base + @as(i32, @intFromFloat(base_scaled)) + delta);
}

fn populateBattleProperties(map: *Property.Map) void {
    map.set(.HpMaxBattle, map.get(.HpMax));
    map.set(.AtkBattle, map.get(.Atk));
    map.set(.BreakStunBattle, map.get(.BreakStun));
    map.set(.SkipDefAtkBattle, map.get(.SkipDefAtk));
    map.set(.DefBattle, map.get(.Def));
    map.set(.CritBattle, map.get(.Crit));
    map.set(.CritDmgBattle, map.get(.CritDmg));
    map.set(.SharpCriticalDamageBattle, map.get(.SharpCriticalDamage));
    map.set(.SpRecoverBattle, map.get(.SpRecover));
    map.set(.ElementMysteryBattle, map.get(.ElementMystery));
    map.set(.ElementAbnormalPowerBattle, map.get(.ElementAbnormalPower));
    map.set(.AddedDamageRatioBattle, map.get(.AddedDamageRatio));
    map.set(.AddedDamageRatioPhysicsBattle, map.get(.AddedDamageRatioPhysics));
    map.set(.AddedDamageRatioFireBattle, map.get(.AddedDamageRatioFire));
    map.set(.AddedDamageRatioIceBattle, map.get(.AddedDamageRatioIce));
    map.set(.AddedDamageRatioElecBattle, map.get(.AddedDamageRatioElec));
    map.set(.AddedDamageRatioEtherBattle, map.get(.AddedDamageRatioEther));
    map.set(.RpRecoverBattle, map.get(.RpRecover));
    map.set(.SkipDefDamageRatioBattle, map.get(.SkipDefDamageRatio));
    map.set(.AddedDamageRatioWindBattle, map.get(.AddedDamageRatioWind));
    map.set(.EpRecoverBattle, map.get(.EpRecover));
    map.add(.PenRatioBattle, map.get(.Pen));
    map.add(.PenDeltaBattle, map.get(.PenValue));
}

pub const Property = enum(u16) {
    None = 0,
    Hp = 1,
    HpMax = 111,
    SpMax = 115,
    RpMax = 119,
    EpMax = 120,
    Atk = 121,
    BreakStun = 122,
    SkipDefAtk = 123,
    Def = 131,
    Crit = 201,
    CritDmg = 211,
    SharpCriticalDamage = 213,
    Pen = 231,
    PenValue = 232,
    SpRecover = 305,
    AddedDamageRatio = 307,
    ElementMystery = 312,
    ElementAbnormalPower = 314,
    AddedDamageRatioPhysics = 315,
    AddedDamageRatioFire = 316,
    AddedDamageRatioIce = 317,
    AddedDamageRatioElec = 318,
    AddedDamageRatioEther = 319,
    RpRecover = 320,
    SkipDefDamageRatio = 322,
    AddedDamageRatioWind = 323,
    EpRecover = 324,
    // battle
    HpMaxBattle = 1111,
    AtkBattle = 1121,
    BreakStunBattle = 1122,
    SkipDefAtkBattle = 1123,
    DefBattle = 1131,
    CritBattle = 1201,
    CritDmgBattle = 1211,
    SharpCriticalDamageBattle = 1213,
    PenRatioBattle = 1231,
    PenDeltaBattle = 1232,
    SpRecoverBattle = 1305,
    AddedDamageRatioBattle = 1307,
    ElementMysteryBattle = 1312,
    ElementAbnormalPowerBattle = 1314,
    AddedDamageRatioPhysicsBattle = 1315,
    AddedDamageRatioFireBattle = 1316,
    AddedDamageRatioIceBattle = 1317,
    AddedDamageRatioElecBattle = 1318,
    AddedDamageRatioEtherBattle = 1319,
    RpRecoverBattle = 1320,
    SkipDefDamageRatioBattle = 1322,
    AddedDamageRatioWindBattle = 1323,
    EpRecoverBattle = 1324,
    // base
    HpMaxBase = 11101,
    SpMaxBase = 11501,
    RpMaxBase = 11901,
    EpMaxBase = 12001,
    AtkBase = 12101,
    BreakStunBase = 12201,
    SkipDefAtkBase = 12301, // ?? client has 12205 for some reason
    DefBase = 13101,
    CritBase = 20101,
    CritDmgBase = 21101,
    SharpCriticalDamageBase = 21301,
    PenBase = 23101,
    PenValueBase = 23201,
    SpRecoverBase = 30501,
    ElementMysteryBase = 31201,
    ElementAbnormalPowerBase = 31401,
    RpRecoverBase = 32001,
    EpRecoverBase = 32401,
    // ratio
    HpMaxRatio = 11102,
    AtkRatio = 12102,
    BreakStunRatio = 12202,
    DefRatio = 13102,
    SpRecoverRatio = 30502,
    ElementAbnormalPowerRatio = 31402,
    RpRecoverRatio = 32002,
    EpRecoverRatio = 32402,
    // delta
    HpMaxDelta = 11103,
    SpMaxDelta = 11503,
    RpMaxDelta = 11903,
    EpMaxDelta = 12003,
    AtkDelta = 12103,
    BreakStunDelta = 12203,
    SkipDefAtkDelta = 12303, // ?? client has 12205 for some reason
    DefDelta = 13103,
    CritDelta = 20103,
    CritDmgDelta = 21103,
    SharpCriticalDamageDelta = 21303,
    PenDelta = 23103,
    PenValueDelta = 23203,
    SpRecoverDelta = 30503,
    ElementMysteryDelta = 31203,
    ElementAbnormalPowerDelta = 31403,
    RpRecoverDelta = 32003,
    EpRecoverDelta = 32403,
    // damage ratios 1/3
    AddedDamageRatio1 = 30701,
    AddedDamageRatio3 = 30703,
    AddedDamageRatioPhysics1 = 31501,
    AddedDamageRatioPhysics3 = 31503,
    AddedDamageRatioFire1 = 31601,
    AddedDamageRatioFire3 = 31603,
    AddedDamageRatioIce1 = 31701,
    AddedDamageRatioIce3 = 31703,
    AddedDamageRatioElec1 = 31801,
    AddedDamageRatioElec3 = 31803,
    AddedDamageRatioEther1 = 31901,
    AddedDamageRatioEther3 = 31903,
    SkipDefDamageRatio1 = 32201,
    SkipDefDamageRatio3 = 32203,
    AddedDamageRatioWind1 = 32301,
    AddedDamageRatioWind3 = 32303,
    _,

    pub const count = @typeInfo(Property).@"enum".field_names.len;

    pub const Index = Index: {
        const field_names = @typeInfo(Property).@"enum".field_names;
        var field_values: [field_names.len]u16 = undefined;

        @setEvalBranchQuota(field_names.len);
        for (&field_values, 0..) |*field_value, field_index|
            field_value.* = @intCast(field_index);

        break :Index @Enum(u16, .exhaustive, field_names, &field_values);
    };

    pub const Map = struct {
        values: [Property.count]i32,

        pub const init: Map = .{
            .values = @splat(0),
        };

        pub fn get(map: *const Map, index: Index) i32 {
            return map.values[@backingInt(index)];
        }

        pub fn set(map: *Map, index: Index, value: i32) void {
            map.values[@backingInt(index)] = value;
        }

        pub fn add(map: *Map, index: Index, value: i32) void {
            map.values[@backingInt(index)] += value;
        }
    };

    pub fn toIndex(property: Property) ?Index {
        @setEvalBranchQuota(Property.count);
        return switch (property) {
            _ => null,
            inline else => |property_comptime| @field(Index, @tagName(property_comptime)),
        };
    }

    pub fn fromIndex(index: Index) Property {
        return std.enums.values(Property)[@backingInt(index)];
    }
};
