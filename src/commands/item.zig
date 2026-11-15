const std = @import("std");

const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn GetWeaponDataCsReq(session: Session(.GetWeaponDataCsReq)) !void {
    var weapon_buffer: [Player.Storage.Weapon.count_max]protobuf.gen.WeaponInfo = undefined;
    var weapon_list: std.ArrayList(protobuf.gen.WeaponInfo) = .initBuffer(&weapon_buffer);
    var weapons = session.player.weapons();

    while (weapons.next()) |weapon_kv| {
        protobuf.pack.weaponInfo(
            weapon_list.addOneAssumeCapacity(),
            weapon_kv,
        );
    }

    return session.respond(.{ .weapon_list = weapon_list.items });
}

pub fn GetEquipDataCsReq(session: Session(.GetEquipDataCsReq)) !void {
    var equip_list: protobuf.pack.EquipInfoList = .empty;
    var equipment = session.player.equipment();

    while (equipment.next()) |equipment_kv| {
        protobuf.pack.equipInfo(
            equip_list.addOneAssumeCapacity(),
            equipment_kv,
        );
    }

    return session.respond(.{
        .equip_list = equip_list.items(.equip_info),
    });
}

pub fn GetItemDataCsReq(session: Session(.GetItemDataCsReq)) !void {
    const materials_count_max = templates.AvatarSkinBase.table.count;
    var materials_buffer: [materials_count_max]protobuf.gen.MaterialInfo = undefined;
    var material_list: std.ArrayList(protobuf.gen.MaterialInfo) = .initBuffer(&materials_buffer);

    for (templates.AvatarSkinBase.table.items(.id)) |id| {
        material_list.appendAssumeCapacity(.{
            .id = id,
            .count = 1,
        });
    }

    return session.respond(.{
        .material_list = material_list.items,
    });
}

pub fn GetWishlistDataCsReq(session: Session(.GetWishlistDataCsReq)) !void {
    return session.respond(.{});
}
