const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const XxHash64 = std.hash.XxHash64;

pub const AvatarBase = struct {
    pub const Table = TemplateTb(AvatarBase, "AvatarBaseTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    code_name: String,
    audio_event_replace_param: String,
    unlockable: bool,
};

pub const AvatarBattle = struct {
    pub const Table = TemplateTb(AvatarBattle, "AvatarBattleTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    hp_max: i32,
    health_growth: i32,
    attack: i32,
    attack_growth: i32,
    defence: i32,
    defence_growth: i32,
    crit: i32,
    crit_damage: i32,
    crit_res: i32,
    crit_damage_res: i32,
    pen_rate: i32,
    pen_delta: i32,
    luck: i32,
    stun: i32,
    break_stun: i32,
    element_abnormal_power: i32,
    sp_bar_point: i32,
    sp_recover: i32,
    element_mystery: i32,
    rbl: i32,
    rbl_correction_factor: i32,
    rbl_probability: i32,
    weapon_type: i32,
    base_avatar_id: i32,
    rp_recover: i32,
    rp_max: i32,
    ep_recover: i32,
    ep_max: i32,
    sharp_critical_damage: i32,
};

pub const AvatarLevelAdvance = struct {
    pub const Table = TemplateTb(AvatarLevelAdvance, "AvatarLevelAdvanceTemplateTb", .id);
    pub const table: Table = .init();

    avatar_id: u32,
    id: u32,
    hp_max: i32,
    attack: i32,
    defence: i32,

    pub fn getByIdAndRank(avatar_id: u32, rank: u32) ?AvatarLevelAdvance {
        for (
            table.items(.avatar_id),
            table.items(.id),
            0..,
        ) |template_avatar_id, template_rank, template_index| {
            if (avatar_id == template_avatar_id and
                rank == template_rank)
                return table.getAtIndex(template_index);
        }

        return null;
    }
};

pub const AvatarPassiveSkill = struct {
    pub const Table = TemplateTb(AvatarPassiveSkill, "AvatarPassiveSkillTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    avatar_id: u32,
    min_passive_skill_level: u32,
    unlock_passive_skill_level: u32,
    properties: [2]PropertyValue.Optional,

    pub fn getByAvatarIdAndLevel(avatar_id: u32, level: u32) ?AvatarPassiveSkill {
        const skill_id = avatar_id * 1000 + level;
        return table.getByKey(skill_id);
    }
};

pub const AvatarSpecialAwaken = struct {
    pub const Table = TemplateTb(AvatarSpecialAwaken, "AvatarSpecialAwakenTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    avatar_id: u32,
    index: u32,

    pub fn isAvailableForAvatar(avatar_id: u32) bool {
        return mem.findScalar(u32, table.items(.avatar_id), avatar_id) != null;
    }

    pub fn getByAvatarIdAndIndex(avatar_id: u32, index: u32) ?AvatarSpecialAwaken {
        for (
            table.items(.avatar_id),
            table.items(.index),
            0..,
        ) |template_avatar_id, template_awake_index, template_index| {
            if (template_avatar_id == avatar_id and template_awake_index == index)
                return table.getAtIndex(template_index);
        }

        return null;
    }
};

pub const PropertyValue = extern struct {
    id: u32,
    value: i32,

    pub const Optional = extern struct {
        id: u32,
        value: i32,

        pub fn unwrap(optional: Optional) ?PropertyValue {
            if (optional.id == 0) return null;

            return .{ .id = optional.id, .value = optional.value };
        }
    };
};

pub const UnlockConfig = struct {
    pub const Table = TemplateTb(UnlockConfig, "UnlockConfigTemplateTb", .id);
    pub const table: Table = .init();

    id: i32,
};

pub const Weapon = struct {
    pub const Table = TemplateTb(Weapon, "WeaponTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    weapon_name: String,
    avatar_id: u32,
    base_property: PropertyValue,
    rand_property: PropertyValue,
};

pub const WeaponLevel = struct {
    pub const Table = TemplateTb(WeaponLevel, "WeaponLevelTemplateTb", .rarity);
    pub const table: Table = .init();

    rarity: u32,
    level: u32,
    rate: u32,
    exp: u32,

    pub fn getByWeaponIdAndLevel(id: u32, level: u32) ?WeaponLevel {
        const rarity = @divFloor(id, 1000) % 10;

        for (
            table.items(.rarity),
            table.items(.level),
            0..,
        ) |template_rarity, template_level, template_index| {
            if (rarity == template_rarity and
                level == template_level)
                return table.getAtIndex(template_index);
        }

        return null;
    }
};

pub const WeaponStar = struct {
    pub const Table = TemplateTb(WeaponStar, "WeaponStarTemplateTb", .rarity);
    pub const table: Table = .init();

    rarity: u32,
    star: u32,
    min_level: u32,
    max_level: u32,
    base_rate: u32,
    rand_rate: u32,

    pub fn getByWeaponIdAndStar(id: u32, star: u32) ?WeaponStar {
        const rarity = @divFloor(id, 1000) % 10;

        for (
            table.items(.rarity),
            table.items(.star),
            0..,
        ) |template_rarity, template_star, template_index| {
            if (rarity == template_rarity and
                star == template_star)
                return table.getAtIndex(template_index);
        }

        return null;
    }
};

pub const Equipment = struct {
    pub const Table = TemplateTb(Equipment, "EquipmentTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
};

pub const EquipmentLevel = struct {
    pub const Table = TemplateTb(EquipmentLevel, "EquipmentLevelTemplateTb", .rarity);
    pub const table: Table = .init();

    rarity: u32,
    level: u32,
    enhance_rate: i32,

    pub fn getByEquipmentIdAndLevel(id: u32, level: u32) ?EquipmentLevel {
        const rarity = (id / 10) % 10;

        for (
            table.items(.rarity),
            table.items(.level),
            0..,
        ) |template_rarity, template_level, template_index| {
            if (rarity == template_rarity and
                level == template_level)
                return table.getAtIndex(template_index);
        }

        return null;
    }
};

pub const EquipmentSuit = struct {
    pub const Table = TemplateTb(EquipmentSuit, "EquipmentSuitTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    primary_condition: u32,
    primary_suit_properties: [2]PropertyValue.Optional,
};

pub const TeleportConfig = struct {
    pub const Table = TemplateTb(TeleportConfig, "TeleportConfigTemplateTb", .id);
    pub const table: Table = .init();

    id: i32,
    client_visible: u32,
};

pub const UrbanAreaMap = struct {
    pub const Table = TemplateTb(UrbanAreaMap, "UrbanAreaMapTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
};

pub const UrbanAreaMapGroup = struct {
    pub const Table = TemplateTb(UrbanAreaMapGroup, "UrbanAreaMapGroupTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
};

pub const SectionConfig = struct {
    pub const Table = TemplateTb(SectionConfig, "SectionConfigTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    default_transform: String,
    display_name: String,
};

pub const MainCityObject = struct {
    pub const Table = TemplateTb(MainCityObject, "MainCityObjectTemplateTb", .tag);
    pub const table: Table = .init();

    tag: u32,
    create_position: String,
    default_interact_ids: [2]OptionalInteractId,

    pub const OptionalInteractId = enum(u32) {
        zero = 0,
        _,

        pub fn unwrap(id: OptionalInteractId) ?u32 {
            return switch (id) {
                .zero => null,
                _ => @backingInt(id),
            };
        }
    };
};

pub const MainCityDefaultObject = struct {
    pub const Table = TemplateTb(MainCityDefaultObject, "MainCityDefaultObjectTemplateTb", .tag);
    pub const table: Table = .init();

    tag: u32,
};

pub const NpcTransform = struct {
    pub const Table = TemplateTb(NpcTransform, "NPCTransformSplitTb", .name_hash);
    pub const table: Table = .init();

    name_hash: u64,
    section_id: u32,

    pub fn getIndexByName(name: []const u8) ?u32 {
        if (name.len == 0) return null;

        var utf16_buffer: [1024]u16 = undefined;
        const utf16_len = std.unicode.utf8ToUtf16Le(&utf16_buffer, name) catch return null;
        const utf16_bytes: []u8 = @ptrCast(utf16_buffer[0..utf16_len]);

        const hash = XxHash64.hash(0, utf16_bytes);

        return table.getIndexByKey(hash);
    }
};

pub const ZoneInfo = struct {
    pub const Table = TemplateTb(ZoneInfo, "ZoneInfoTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    layer_id: u32,
    layer_index: u32,
    group_id: u32,
    entrance_id: u32,

    pub fn getByZoneIdAndLayerIndex(zone_id: u32, layer_index: u32) ?ZoneInfo {
        for (
            table.items(.id),
            table.items(.layer_index),
            0..,
        ) |template_zone_id, template_layer_index, template_index| {
            if (template_zone_id == zone_id and template_layer_index == layer_index)
                return table.getAtIndex(template_index);
        }

        return null;
    }

    pub fn isFreeTraining(zone_info: *const ZoneInfo) bool {
        return zone_info.entrance_id == 901;
    }
};

pub const BattleEventConfig = struct {
    pub const Table = TemplateTb(BattleEventConfig, "BattleEventConfigTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    local_play_type: u32,
};

pub const PlayTypeMapping = struct {
    pub const Table = TemplateTb(PlayTypeMapping, "PlayTypeMappingTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    local_play_type: u32,

    pub fn getByLocalPlayType(lpt: u32) ?PlayTypeMapping {
        const index = mem.findScalar(u32, table.items(.local_play_type), lpt) orelse return null;
        return table.getAtIndex(index);
    }
};

pub const HadalZoneQuest = struct {
    pub const Table = TemplateTb(HadalZoneQuest, "HadalZoneQuestTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    layer_id: u32,

    pub fn getByLayerId(layer_id: u32) ?HadalZoneQuest {
        const index = mem.findScalar(u32, table.items(.layer_id), layer_id) orelse return null;
        return table.getAtIndex(index);
    }
};

pub const Text = struct {
    pub const Table = TemplateTb(Text, "assets/textmap.bin", .key);
    pub const table: Table = .init();

    key: String,
    value: String,

    pub const Map = struct {
        inner: std.array_hash_map.String([]const u8),

        pub fn init(gpa: Allocator) Allocator.Error!Map {
            var map: std.array_hash_map.String([]const u8) = .empty;
            try map.ensureTotalCapacity(gpa, table.count);
            errdefer comptime unreachable;

            for (table.items(.key), table.items(.value)) |key, value| {
                map.putAssumeCapacity(table.getString(key), table.getString(value));
            }

            return .{ .inner = map };
        }

        pub fn deinit(textmap: *Text.Map, gpa: Allocator) void {
            textmap.inner.deinit(gpa);
        }

        pub fn get(textmap: *const Text.Map, key: []const u8) ?[]const u8 {
            return textmap.inner.get(key);
        }
    };
};

pub const String = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

fn TemplateTb(
    comptime Template: type,
    comptime file_name: []const u8,
    comptime key_field: @EnumLiteral(),
) type {
    const struct_info = @typeInfo(Template).@"struct";
    const field_names = struct_info.field_names;

    return struct {
        const Tb = @This();

        const bytes align(@alignOf(u32)) = @embedFile(file_name).*;

        const Arrays = Arrays: {
            var field_types: [struct_info.field_names.len]type = undefined;
            for (struct_info.field_types, &field_types) |Item, *Slice|
                Slice.* = []const Item;

            break :Arrays @Struct(
                .auto,
                null,
                struct_info.field_names,
                &field_types,
                &@splat(.{}),
            );
        };

        const Offsets = @Struct(
            .@"extern",
            null,
            field_names,
            &@splat(u32),
            &@splat(.{}),
        );

        const data_start = arrays_base: {
            const first_field_alignment = @alignOf(struct_info.field_types[0]);
            const post_header = @sizeOf(u32) + @sizeOf(Offsets);
            break :arrays_base mem.alignForward(usize, post_header, first_field_alignment);
        };

        count: u32,
        arrays: Arrays,
        string_table: []const u8,
        /// Biased towards cheap linear search.
        index_by_key: std.array_hash_map.Custom(void, void, void, false),

        pub const Field = std.meta.FieldEnum(Template);

        fn init() Tb {
            const item_count = @as(*const u32, @ptrCast(bytes[0..4])).*;
            const offsets: *const Offsets = @ptrCast(bytes[4..][0..@sizeOf(Offsets)]);
            const first_field_alignment = @alignOf(struct_info.field_types[0]);

            const string_table_offset =
                @field(offsets, field_names[field_names.len - 1]) +
                (@sizeOf(@FieldType(Template, field_names[field_names.len - 1])) * item_count);

            const data: []align(first_field_alignment) const u8 = @alignCast(bytes[data_start..]);
            var arrays: Arrays = undefined;

            inline for (field_names, struct_info.field_types) |field_name, FieldType| {
                const offset = @field(offsets, field_name);
                @field(arrays, field_name) =
                    @as([*]const FieldType, @ptrCast(data.ptr[offset..]))[0..item_count];
            }

            return .{
                .count = item_count,
                .arrays = arrays,
                .string_table = data[string_table_offset..],
                .index_by_key = .{ .entries = .{
                    .bytes = undefined,
                    .len = item_count,
                    .capacity = item_count,
                } },
            };
        }

        const Key = @FieldType(Template, @tagName(key_field));

        pub fn getIndexByKey(tb: *const Tb, key: Key) ?u32 {
            const Adapter = struct {
                keys: []const Key,

                pub fn eql(context: @This(), a: Key, b_void: void, b_map_index: usize) bool {
                    _ = b_void;
                    return a == context.keys[b_map_index];
                }

                pub fn hash(context: @This(), a: Key) u32 {
                    _ = context;
                    return @truncate(a);
                }
            };

            const adapter: Adapter = .{ .keys = tb.items(key_field) };
            if (tb.index_by_key.getIndexAdapted(key, adapter)) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub fn items(tb: *const Tb, comptime which: Field) @FieldType(Arrays, @tagName(which)) {
            return @field(tb.arrays, @tagName(which));
        }

        pub fn getAtIndex(tb: *const Tb, index: usize) Template {
            var template: Template = undefined;
            inline for (@typeInfo(Template).@"struct".field_names) |field_name| {
                @field(template, field_name) = @field(tb.arrays, field_name)[index];
            }

            return template;
        }

        pub fn getByKey(tb: *const Tb, key: Key) ?Template {
            const index = tb.getIndexByKey(key) orelse return null;
            return tb.getAtIndex(index);
        }

        pub fn getString(tb: *const Tb, string: String) [:0]const u8 {
            switch (string) {
                .empty => return "",
                _ => {
                    const start = @backingInt(string);
                    const ptr: [*:0]const u8 = @ptrCast(tb.string_table[start..].ptr);
                    return mem.span(ptr);
                },
            }
        }
    };
}
