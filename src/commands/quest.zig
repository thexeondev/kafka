const std = @import("std");

const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const battle = remielle.battle;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;
const StaticIntMap = remielle.StaticIntMap;

pub fn GetQuestDataCsReq(session: Session(.GetQuestDataCsReq)) !void {
    const request = try session.decodeBody();

    return session.respond(.{
        .quest_type = request.quest_type,
        .quest_data = .{},
    });
}

pub fn GetHollowDataCsReq(session: Session(.GetHollowDataCsReq)) !void {
    return session.respond(.{ .hollow_data = .{} });
}

pub fn GetArchiveDataCsReq(session: Session(.GetArchiveDataCsReq)) !void {
    return session.respond(.{ .archive_data = .{} });
}

pub fn StartTrainingQuestCsReq(session: Session(.StartTrainingQuestCsReq)) !void {
    var request = try session.decodeBody();

    var avatar_id_buffer: [3]u32 = undefined;
    var avatar_id_list: std.ArrayList(u32) = .initBuffer(&avatar_id_buffer);

    while (try request.avatar_id_list.next()) |avatar_id|
        avatar_id_list.appendBounded(avatar_id) catch
            return session.fail(.RET_AVATAR_PARAM_ERROR);

    if (avatar_id_list.items.len == 0)
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    var avatar_info_list: protobuf.pack.AvatarInfoList = .empty;
    var avatars = session.player.avatars();
    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(avatar_info_list.addOneAssumeCapacity(), avatar);

    try session.notify(protobuf.gen.EnterSceneScNotify, .{
        .scene = .{
            .scene_type = 3,
            .scene_id = 19800014,
            .local_play_type = 290,
            .play_type_id = 19,
            .fight_scene_data = .{ .scene_reward = .{}, .scene_perform = .{} },
        },
        .dungeon = .{
            .quest_id = request.quest_id,
            .dungeon_package_info = .{ .avatar_list = avatar_info_list.items(.avatar_info) },
        },
    });

    return session.success();
}

pub fn EndBattleCsReq(session: Session(.EndBattleCsReq)) !void {
    return session.respond(.{ .fight_settle = .{} });
}

const hadal_scene_by_group: StaticIntMap(u32, u32) = .initComptime(&.{
    .{ 101, 6100100 },
    .{ 102, 6100200 },
    .{ 201, 6200100 },
    .{ 202, 6100200 },
    .{ 301, 6200100 },
    .{ 1001, 6900100 },
    .{ 1002, 6900100 },
});

const hadal_zone_free_training_scene_id = 6900404;
const hadal_zone_impact_scene_id = 6201050;

pub fn BeginHadalBattleCsReq(session: Session(.BeginHadalBattleCsReq)) !void {
    const log = std.log.scoped(.BeginHadalBattleCsReq);
    var request = try session.decodeBody();

    var first_room_avatar_id_list_buffer: [3]u32 = undefined;
    var first_room_avatar_id_list: std.ArrayList(u32) =
        .initBuffer(&first_room_avatar_id_list_buffer);

    while (try request.first_room_avatar_id_list.next()) |id| {
        first_room_avatar_id_list.appendBounded(id) catch
            return session.fail(.RET_AVATAR_PARAM_ERROR);
    }

    var second_room_avatar_id_list_buffer: [3]u32 = undefined;
    var second_room_avatar_id_list: std.ArrayList(u32) =
        .initBuffer(&second_room_avatar_id_list_buffer);

    while (try request.second_room_avatar_id_list.next()) |id| {
        second_room_avatar_id_list.appendBounded(id) catch
            return session.fail(.RET_AVATAR_PARAM_ERROR);
    }

    var dungeon_package_buffer: protobuf.pack.DungeonPackageBuffer = .init;
    var avatars = session.player.avatars();
    var weapons = session.player.weapons();
    var equipment = session.player.equipment();

    const dungeon_package =
        protobuf.pack.dungeonPackage(&dungeon_package_buffer, &avatars, &weapons, &equipment);

    var avatar_unit_list: protobuf.pack.AvatarUnitInfoList = .empty;
    for (@as([]const []const u32, &.{
        first_room_avatar_id_list.items,
        second_room_avatar_id_list.items,
    })) |avatar_id_list| {
        for (avatar_id_list) |avatar_id| {
            const avatar_init = session.player.getBattleAvatarInitById(avatar_id) orelse
                return session.fail(.RET_AVATAR_PARAM_ERROR);

            var property_map: battle.Property.Map = .init;
            battle.makeAvatarProperties(&property_map, avatar_init);

            protobuf.pack.avatarUnitInfo(
                avatar_unit_list.addOneAssumeCapacity(),
                avatar_id,
                &property_map,
            );
        }
    }

    const zone_info = templates.ZoneInfo.getByZoneIdAndLayerIndex(
        request.zone_id,
        request.layer_index,
    ) orelse
        return session.fail(.RET_QUEST_NOT_FOUND);

    const scene_id = if (zone_info.isFreeTraining()) free_training: {
        break :free_training hadal_zone_free_training_scene_id;
    } else if (request.room_index != 0) impact: {
        break :impact hadal_zone_impact_scene_id +| request.room_index;
    } else if (hadal_scene_by_group.get(zone_info.group_id)) |scene_id_base| from_base: {
        break :from_base scene_id_base +| request.layer_index;
    } else {
        log.debug("unknown ZoneInfo group_id {d}", .{zone_info.group_id});
        return session.fail(.RET_QUEST_NOT_FOUND);
    };

    const battle_event = templates.BattleEventConfig.table.getByKey(scene_id) orelse {
        log.debug(
            "couldn't find BattleEventConfig for scene {d} (zone: {d}, layer: {d})",
            .{ scene_id, request.zone_id, request.layer_index },
        );
        return session.fail(.RET_SCENE_NOT_FOUND);
    };

    const play_type = templates.PlayTypeMapping.getByLocalPlayType(battle_event.local_play_type) orelse
        return session.fail(.RET_SCENE_NOT_RIGHT);

    const hadal_zone_quest = templates.HadalZoneQuest.getByLayerId(scene_id) orelse
        return session.fail(.RET_SCENE_NOT_RIGHT);

    try session.notify(protobuf.gen.EnterSceneScNotify, .{
        .scene = .{
            .scene_type = 9, // Hadal
            .scene_id = 0,
            .local_play_type = battle_event.local_play_type,
            .play_type_id = play_type.id,
            .hadal_zone_scene_data = .{
                .zone_id = request.zone_id,
                .layer_index = request.layer_index,
                .layer_item_id = request.layer_item_id,
                .room_index = request.room_index,
                .first_room_avatar_id_list = first_room_avatar_id_list.items,
                .second_room_avatar_id_list = second_room_avatar_id_list.items,
            },
        },
        .dungeon = .{
            .quest_id = hadal_zone_quest.id,
            .quest_type = 13, // HadalZone
            .dungeon_package_info = dungeon_package,
            .avatar_list = avatar_unit_list.items(.info),
        },
    });

    return session.respond(.{});
}
