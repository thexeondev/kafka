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
    const request = try session.decodeBody();

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
    const first_room_avatar_id_list =
        try request.first_room_avatar_id_list.toSlice(&first_room_avatar_id_list_buffer) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    var second_room_avatar_id_list_buffer: [3]u32 = undefined;
    const second_room_avatar_id_list =
        try request.second_room_avatar_id_list.toSlice(&second_room_avatar_id_list_buffer) orelse
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    if (first_room_avatar_id_list.len == 0 and
        second_room_avatar_id_list.len == 0)
        return session.fail(.RET_AVATAR_PARAM_ERROR);

    const zone_info = templates.ZoneInfo.get(.{
        .zone_id = request.zone_id,
        .layer_index = request.layer_index,
        .sub_layer_index = request.sub_layer_index,
    }) orelse
        return session.fail(.RET_QUEST_NOT_FOUND);

    const scene_id = if (zone_info.isFreeTraining()) free_training: {
        break :free_training hadal_zone_free_training_scene_id;
    } else if (request.sub_layer_index != 0) impact: {
        break :impact hadal_zone_impact_scene_id +| request.sub_layer_index;
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

    const battle_options: Player.Temporaries.Battle.Hadal.Options = .{
        .zone_id = request.zone_id,
        .layer_id = zone_info.layer_id,
        .layer_index = request.layer_index,
        .layer_item_id = request.layer_item_id,
        .sub_layer_index = request.sub_layer_index,
        .first_room_avatar_id_list = .fromSlice(first_room_avatar_id_list),
        .second_room_avatar_id_list = .fromSlice(second_room_avatar_id_list),
        .first_room_buddy_id = request.first_room_buddy_id,
        .second_room_buddy_id = request.second_room_buddy_id,
        .scene_id = scene_id,
        .quest_id = hadal_zone_quest.id,
        .play_type_id = play_type.id,
    };

    var avatar_unit_buffer: protobuf.pack.AvatarUnitInfoList = .empty;
    const avatar_unit_list = buildAvatarUnitList(session.player, &avatar_unit_buffer, &.{
        first_room_avatar_id_list,
        second_room_avatar_id_list,
    }) orelse return session.fail(.RET_AVATAR_PARAM_ERROR);

    try notifyEnterHadalScene(session.typeErased(), avatar_unit_list, &battle_options);

    session.player.temp.cur_battle = .{ .hadal = .init(battle_options) };
    return session.respond(.{});
}

pub fn RebeginHadalBattleCsReq(session: Session(.RebeginHadalBattleCsReq)) !void {
    const cur_battle = session.player.temp.cur_battle orelse
        return session.fail(.RET_DUNGEON_NO_RETRY);

    switch (cur_battle) {
        .hadal => |hadal| {
            var avatar_unit_buffer: protobuf.pack.AvatarUnitInfoList = .empty;
            const avatar_unit_list = buildAvatarUnitList(session.player, &avatar_unit_buffer, &.{
                hadal.options.first_room_avatar_id_list.toSlice(),
                hadal.options.second_room_avatar_id_list.toSlice(),
            }) orelse return session.fail(.RET_AVATAR_PARAM_ERROR);

            try notifyEnterHadalScene(session.typeErased(), avatar_unit_list, &hadal.options);
            session.player.temp.cur_battle = .{ .hadal = .init(hadal.options) };
        },
    }

    return session.respond(.{});
}

pub fn HadalStatEndRoomCsReq(session: Session(.HadalStatEndRoomCsReq)) !void {
    const request = try session.decodeBody();
    const result = request.result orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    var record = result.battle_data_record orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    const cur_battle = &(session.player.temp.cur_battle orelse return session.fail(.RET_DUNGEON_NOT_FOUND));
    if (cur_battle.kind() != .hadal) return session.fail(.RET_SCENE_NOT_RIGHT);

    var summary: Player.Temporaries.Battle.Summary = .init;
    if (record.buddy_member_data) |member| if (member.buddy_id != 0) {
        summary.buddy_maybe = .{
            .template_id = member.buddy_id,
            .damage = member.damage,
            .stun = member.stun,
            .element_abnormal_accumulation = member.element_abnormal_accumulation,
            .recover = member.recover,
            .shield = member.shield,
        };
    };

    while (try record.avatar_member_list.next()) |member| {
        summary.appendAvatar(.{
            .template_id = member.avatar_id,
            .damage = member.damage,
            .stun = member.stun,
            .element_abnormal_accumulation = member.element_abnormal_accumulation,
            .recover = member.recover,
            .shield = member.shield,
        }) catch |err| switch (err) {
            error.NoSpaceLeft => return session.fail(.RET_AVATAR_PARAM_ERROR),
        };
    }

    cur_battle.hadal.appendRoomSummary(summary) catch |err| switch (err) {
        error.NoSpaceLeft => return session.fail(.RET_SCENE_NOT_RIGHT),
    };

    return session.success();
}

pub fn EndBattleCsReq(session: Session(.EndBattleCsReq)) !void {
    const request = try session.decodeBody();
    const result = request.fight_result orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    if (session.player.temp.cur_battle) |cur_battle| switch (cur_battle) {
        .hadal => |hadal| {
            const layer_info = templates.LayerInfo.table.getByKey(hadal.options.layer_id) orelse
                return session.fail(.RET_SCENE_NOT_RIGHT);

            var record_pack_buffer: protobuf.pack.BattleDataRecordMap = .empty;

            for (hadal.roomSummaries(), 0..) |*summary, room_index| {
                const room_id = layer_info.room_ids[room_index].unwrap() orelse
                    return session.fail(.RET_SCENE_NOT_RIGHT);

                protobuf.pack.battleDataRecord(
                    record_pack_buffer.addOneAssumeCapacity(),
                    room_id,
                    summary,
                );
            }

            var contrib_buffer: [6]protobuf.gen.AvatarContributionInfo = undefined;
            var contrib_list: std.ArrayList(protobuf.gen.AvatarContributionInfo) =
                .initBuffer(&contrib_buffer);

            const avatar_vec: [2][]const u32 = .{
                hadal.options.first_room_avatar_id_list.toSlice(),
                hadal.options.second_room_avatar_id_list.toSlice(),
            };
            for (avatar_vec) |list| for (list) |avatar_id| {
                contrib_list.appendAssumeCapacity(.{
                    .avatar_id = avatar_id,
                    .contribution = 1337,
                });
            };

            try session.notify(protobuf.gen.DungeonQuestFinishedScNotify, .{
                .quest_id = hadal.options.quest_id,
                .rank = if (result.result > 0) 4 else 0,
                .result = @bitCast(result.result),
                .avatar_contribution_list = contrib_list.items,
                .dungeon_summary = .{ .hadal_summary = .{
                    .battle_data_record_map = record_pack_buffer.items(.record_key_value),
                } },
            });
        },
    };

    return session.respond(.{ .fight_settle = .{} });
}

fn buildAvatarUnitList(
    player: *Player,
    pack_buffer: *protobuf.pack.AvatarUnitInfoList,
    avatar_id_vec: []const []const u32,
) ?[]const protobuf.gen.AvatarUnitInfo {
    for (avatar_id_vec) |avatar_id_list| {
        for (avatar_id_list) |avatar_id| {
            const avatar_init = player.getBattleAvatarInitById(avatar_id) orelse
                return null;

            var property_map: battle.Property.Map = .init;
            battle.makeAvatarProperties(&property_map, avatar_init);

            protobuf.pack.avatarUnitInfo(
                pack_buffer.addOneAssumeCapacity(),
                avatar_id,
                &property_map,
            );
        }
    }

    return pack_buffer.items(.info);
}

fn notifyEnterHadalScene(
    session: *remielle.session.TypeErased,
    avatar_unit_list: []const protobuf.gen.AvatarUnitInfo,
    options: *const Player.Temporaries.Battle.Hadal.Options,
) !void {
    var dungeon_package_buffer: protobuf.pack.DungeonPackageBuffer = .init;
    var avatars = session.player.avatars();
    var weapons = session.player.weapons();
    var equipment = session.player.equipment();

    const dungeon_package =
        protobuf.pack.dungeonPackage(&dungeon_package_buffer, &avatars, &weapons, &equipment);

    var buddy_unit_buffer: [3]protobuf.gen.BuddyUnitInfo = undefined;
    var buddy_unit_list: std.ArrayList(protobuf.gen.BuddyUnitInfo) = .initBuffer(&buddy_unit_buffer);
    buddy_unit_list.appendAssumeCapacity(.{
        .buddy_id = templates.BuddyBase.assisting_buddy_id,
        .type = .ASSISTING,
    });

    for (@as([]const u32, &.{
        options.first_room_buddy_id,
        options.second_room_buddy_id,
    })) |buddy_id| {
        if (buddy_id != 0) buddy_unit_list.appendAssumeCapacity(.{
            .buddy_id = buddy_id,
            .type = .FIGHTING,
        });
    }

    const play_type = templates.PlayTypeMapping.table.getByKey(options.play_type_id).?;

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = .{
            .scene_type = 9, // Hadal
            .scene_id = options.scene_id,
            .local_play_type = play_type.local_play_type,
            .play_type_id = play_type.id,
            .hadal_zone_scene_data = .{
                .zone_id = options.zone_id,
                .layer_index = options.layer_index,
                .layer_item_id = options.layer_item_id,
                .sub_layer_index = options.sub_layer_index,
                .first_room_avatar_id_list = options.first_room_avatar_id_list.toSlice(),
                .second_room_avatar_id_list = options.second_room_avatar_id_list.toSlice(),
                .first_room_buddy_id = options.first_room_buddy_id,
                .second_room_buddy_id = options.second_room_buddy_id,
            },
        },
        .dungeon = .{
            .quest_id = options.quest_id,
            .quest_type = 13, // HadalZone
            .dungeon_package_info = dungeon_package,
            .avatar_list = avatar_unit_list,
            .buddy_list = buddy_unit_list.items,
        },
    });
}
