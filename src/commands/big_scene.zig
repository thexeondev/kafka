const std = @import("std");
const ArrayList = std.ArrayList;

const remielle = @import("../remielle.zig");
const assets = remielle.assets;
const Player = remielle.Player;
const Session = remielle.Session;
const battle = remielle.battle;
const protobuf = remielle.protobuf;
const gen = remielle.protobuf.gen;

pub fn GetBigSceneDataCsReq(session: Session(.GetBigSceneDataCsReq)) !void {
    var scene_avatar_buffer: [Player.Storage.Avatar.count_max]gen.BigSceneAvatarInfo = undefined;
    var scene_avatar_list: ArrayList(gen.BigSceneAvatarInfo) = .initBuffer(&scene_avatar_buffer);

    var avatars = session.player.avatars();
    while (avatars.next()) |avatar| {
        protobuf.pack.bigSceneAvatarInfoMinimal(scene_avatar_list.addOneAssumeCapacity(), .{
            .avatar_id = avatar.id,
            .hp_percentage = 100,
            .operation = .NONE,
        });
    }

    var team_avatar_list: protobuf.pack.BigSceneAvatarList = .empty;
    const team = session.player.getBigSceneTeam();
    for (team.lineup_avatar_list) |avatar_id_maybe| {
        const avatar_id = avatar_id_maybe orelse continue;
        const avatar_init = session.player.getBattleAvatarInitById(avatar_id).?;

        var property_map: battle.Property.Map = .init;
        battle.makeAvatarProperties(&property_map, avatar_init);

        protobuf.pack.bigSceneAvatarInfo(team_avatar_list.addOneAssumeCapacity(), .{
            .avatar_id = avatar_id,
            .hp_percentage = 100,
            .operation = .NONE,
            .property_map = &property_map,
        });
    }

    return session.respond(.{
        .big_scene_team = .{
            .scene_avatar_list = scene_avatar_list.items,
            .cur_scene_avatar_list = team_avatar_list.items(.info),
        },
    });
}

pub fn BigSceneTeamReplaceCsReq(session: Session(.BigSceneTeamReplaceCsReq)) !void {
    var request = try session.decodeBody();

    var new_team: Player.BigSceneTeam = .empty;
    while (try request.new_team_avatar_id_list.next()) |avatar_id| {
        if (!session.player.hasAvatarWithId(avatar_id))
            return session.fail(.RET_AVATAR_PARAM_ERROR);

        new_team.addAvatarId(avatar_id) catch |err| switch (err) {
            error.NoSpaceLeft,
            error.DuplicatedId,
            => return session.fail(.RET_AVATAR_PARAM_ERROR),
        };
    }

    session.player.replaceBigSceneTeam(new_team);
    return session.success();
}

pub fn EnterFloorCsReq(session: Session(.EnterFloorCsReq)) !void {
    const log = std.log.scoped(.EnterFloorCsReq);

    const request = try session.decodeBody();
    if (assets.Floor.table.get(request.floor_id) == null) {
        log.debug("floor {d} doesn't exist", .{request.floor_id});
        return session.fail(.RET_SCENE_NOT_FOUND);
    }

    const rollback_point = request.rollback_point orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    const pos = rollback_point.position orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    const rot = rollback_point.rotation orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    session.player.enterBigSceneFloor(.{
        .floor_id = request.floor_id,
        .position = .{ pos.x, pos.y, pos.z },
        .rotation = .{ rot.x, rot.y, rot.z },
    });

    return session.success();
}

pub fn EnterFloorDoneCsReq(session: Session(.EnterFloorDoneCsReq)) !void {
    const floor_id = session.player.storage.big_scene.cur_floor_id.unwrap() orelse {
        return session.fail(.RET_SCENE_NOT_RIGHT);
    };

    try notifyMasterEntityAppearance(session.typeErased());

    const floor = assets.Floor.table.get(floor_id).?;
    try notifyGroupMemberCreate(session.typeErased(), &floor);
    try notifyGroupOrders(session.typeErased(), &floor);
    try notifyGroupEntitiesAppearance(session.typeErased(), &floor);

    return session.success();
}

const gadget_count_max = assets.Group.table.gadget_ids.len;

fn notifyGroupMemberCreate(
    session: *remielle.session.TypeErased,
    floor: *const assets.Floor,
) !void {
    var group_member_buffer: [gadget_count_max]gen.GroupMemberId = undefined;
    var group_member_list: ArrayList(gen.GroupMemberId) = .initBuffer(&group_member_buffer);

    for (floor.group_id_list) |group_id| {
        const group = assets.Group.table.getGroupById(group_id).?;
        if ((group.vo_group_type == 1 or group.vo_group_type == 2) and group.group_usage == 0) {
            for (group.gadget_config_ids) |config_id| {
                group_member_list.appendAssumeCapacity(.{
                    .group_id = group_id,
                    .config_id = config_id,
                });
            }
        }
    }

    try session.sink.notify(gen.GroupMemberCreateScNotify, &.{
        .group_member_list = group_member_list.items,
    });
}

fn notifyGroupOrders(
    session: *remielle.session.TypeErased,
    floor: *const assets.Floor,
) !void {
    for (floor.group_id_list) |group_id| {
        var member_config_id_buffer: [gadget_count_max]u32 = undefined;
        var member_config_id_list: ArrayList(u32) = .initBuffer(&member_config_id_buffer);
        const group = assets.Group.table.getGroupById(group_id).?;
        if ((group.vo_group_type == 1 or group.vo_group_type == 2) and group.group_usage == 0) {
            for (group.gadget_config_ids) |config_id| {
                member_config_id_list.appendAssumeCapacity(config_id);
            }

            try session.sink.notify(gen.GroupOrderReadyScNotify, &.{ .group_info = .{
                .group_id = group_id,
                .reason = .{ .group_order_reason = @fromBackingInt(1) },
                .member_config_id_list = member_config_id_list.items,
            } });
        }
    }
}

fn notifyMasterEntityAppearance(session: *remielle.session.TypeErased) !void {
    const avatar_id = session.player.getControlBigSceneAvatarId();
    const entity_id = session.player.nextBigSceneEntityId(.avatar);
    const position = session.player.storage.big_scene.position;

    try session.sink.notify(gen.SceneEntityAppearScNotify, &.{
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

fn notifyGroupEntitiesAppearance(
    session: *remielle.session.TypeErased,
    floor: *const assets.Floor,
) !void {
    var entity_buffer: [128]gen.SceneEntityInfo = undefined;
    var entity_list: ArrayList(gen.SceneEntityInfo) = .initBuffer(&entity_buffer);

    for (floor.group_id_list) |group_id| {
        const group = assets.Group.table.getGroupById(group_id).?;
        if ((group.vo_group_type == 1 or group.vo_group_type == 2) and group.group_usage == 0) {
            for (
                group.gadget_config_ids,
                group.gadget_ids,
                group.gadget_positions,
            ) |config_id, gadget_id, position| {
                const entity_id = session.player.nextBigSceneEntityId(.gadget);

                entity_list.appendBounded(.{
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
                }) catch {
                    defer entity_list.clearRetainingCapacity();
                    try session.sink.notify(gen.SceneEntityAppearScNotify, &.{
                        .appear_type = @fromBackingInt(1),
                        .entity_list = entity_list.items,
                        .param = 0,
                    });
                };
            }
        }
    }

    if (entity_list.items.len != 0) {
        try session.sink.notify(gen.SceneEntityAppearScNotify, &.{
            .param = 0,
            .appear_type = @fromBackingInt(1),
            .entity_list = entity_list.items,
        });
    }
}
