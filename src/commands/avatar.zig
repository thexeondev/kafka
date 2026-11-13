const std = @import("std");

const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn GetAvatarDataCsReq(session: Session(.GetAvatarDataCsReq)) !void {
    var avatar_info_list: protobuf.pack.AvatarInfoList = .empty;
    var avatars = session.player.avatars();

    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(avatar_info_list.addOneAssumeCapacity(), avatar);

    return session.respond(.{
        .avatar_list = avatar_info_list.items(.avatar_info),
    });
}

pub fn AvatarFavoriteCsReq(session: Session(.AvatarFavoriteCsReq)) !void {
    const request = try session.decodeBody();

    var avatar = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    avatar.favorite = request.is_favorite;
    session.player.updateAvatar(avatar);
    return session.success();
}

pub fn WeaponDressCsReq(session: Session(.WeaponDressCsReq)) !void {
    const request = try session.decodeBody();

    const weapon = session.player.getWeaponByUid(request.weapon_uid) orelse
        return session.fail(.RET_ITEM_NOT_FOUND);

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    if (session.player.getAvatarWithWeaponUid(request.weapon_uid)) |previous_owner| {
        var avatar_to_undress = previous_owner;
        avatar_to_undress.weapon_uid_maybe = null;
        session.player.updateAvatar(avatar_to_undress);
    }

    avatar_to_dress.weapon_uid_maybe = request.weapon_uid;

    switch (avatar_to_dress.weapon_show) {
        .unlocked_show, .unlocked_hidden => {},
        .locked => {
            const weapon_template_index = templates.Weapon.table.getIndexByKey(weapon.id).?;
            const weapon_avatar_id = templates.Weapon.table.items(.avatar_id)[weapon_template_index];
            if (weapon_avatar_id == avatar_to_dress.id)
                avatar_to_dress.weapon_show = .unlocked_show;
        },
    }

    session.player.updateAvatar(avatar_to_dress);
    return session.success();
}

pub fn WeaponUnDressCsReq(session: Session(.WeaponUnDressCsReq)) !void {
    const request = try session.decodeBody();

    var avatar_to_undress = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_NO_WEAPON);

    avatar_to_undress.weapon_uid_maybe = null;
    session.player.updateAvatar(avatar_to_undress);

    return session.success();
}

pub fn EquipmentDressCsReq(session: Session(.EquipmentDressCsReq)) !void {
    const request = try session.decodeBody();

    const dress_equipment_type = std.enums.fromInt(Player.Equipment.Type, request.dress_index) orelse
        return session.fail(.RET_AVATAR_INVALID_DRESS_INDEX);

    if (!session.player.hasEquipmentWithUid(request.equip_uid))
        return session.fail(.RET_ITEM_NOT_FOUND);

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    if (session.player.getAvatarWithEquipmentUid(request.equip_uid)) |previous_owner| {
        var avatar_to_undress = previous_owner.avatar;
        avatar_to_undress.dressed_equipment.remove(previous_owner.equipment_type);
        session.player.updateAvatar(avatar_to_undress);
    }

    avatar_to_dress.dressed_equipment.put(dress_equipment_type, request.equip_uid);
    session.player.updateAvatar(avatar_to_dress);

    return session.success();
}

pub fn EquipmentUnDressCsReq(session: Session(.EquipmentUnDressCsReq)) !void {
    var request = try session.decodeBody();

    var avatar_to_undress = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    while (try request.undress_index_list.next()) |undress_index| {
        if (avatar_to_undress.dressed_equipment.count() == 0)
            return session.fail(.RET_AVATAR_INVALID_DRESS_INDEX);

        const equipment_type = std.enums.fromInt(Player.Equipment.Type, undress_index) orelse
            return session.fail(.RET_AVATAR_INVALID_DRESS_INDEX);

        if (avatar_to_undress.dressed_equipment.fetchRemove(equipment_type) == null)
            return session.fail(.RET_AVATAR_DRESS_INDEX_NOT_EQUIPPED);
    }

    session.player.updateAvatar(avatar_to_undress);

    return session.success();
}

pub fn EquipmentSuitDressCsReq(session: Session(.EquipmentSuitDressCsReq)) !void {
    var request = try session.decodeBody();

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    while (try request.param_list.next()) |dress_param| {
        const equipment_type = std.enums.fromInt(Player.Equipment.Type, dress_param.dress_index) orelse
            return session.fail(.RET_AVATAR_INVALID_DRESS_INDEX);

        if (!session.player.hasEquipmentWithUid(dress_param.equip_uid))
            return session.fail(.RET_ITEM_NOT_FOUND);

        if (avatar_to_dress.dressed_equipment.fetchPut(equipment_type, dress_param.equip_uid) != null)
            return session.fail(.RET_AVATAR_INVALID_DRESS_INDEX);
    }

    session.player.updateAvatar(avatar_to_dress);

    return session.success();
}
