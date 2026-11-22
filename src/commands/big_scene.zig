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
    if (!session.player.startBigSceneLogic()) {
        return session.fail(.RET_SCENE_NOT_RIGHT);
    }

    return session.success();
}

pub fn ActiveRollbackPointCsReq(session: Session(.ActiveRollbackPointCsReq)) !void {
    const request = try session.decodeBody();
    const rbp = request.rollback_point orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    const pos = rbp.position orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    const rot = rbp.rotation orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    session.player.updateRollbackPoint(.{
        .position = .{ pos.x, pos.y, pos.z },
        .rotation = .{ rot.x, rot.y, rot.z },
    });

    return session.success();
}

pub fn SceneEntityMoveCsReq(session: Session(.SceneEntityMoveCsReq)) !void {
    var request = try session.decodeBody();
    const master_entity_id = session.player.getMasterViewObjectEntityId() orelse
        return session.fail(.RET_SCENE_NOT_RIGHT);

    if (request.entity_motion) |entity_motion| {
        const pos = entity_motion.position orelse return session.fail(.RET_INVALID_REQUEST_DATA);
        if (entity_motion.entity_id == master_entity_id.toInt()) {
            if (!session.player.updateBigScenePosition(.{ pos.x, pos.y, pos.z }))
                return session.fail(.RET_SCENE_NOT_RIGHT);
        }
    }

    while (try request.motion_list.next()) |entity_motion| {
        const pos = entity_motion.position orelse return session.fail(.RET_INVALID_REQUEST_DATA);
        if (entity_motion.entity_id == master_entity_id.toInt()) {
            if (!session.player.updateBigScenePosition(.{ pos.x, pos.y, pos.z }))
                return session.fail(.RET_SCENE_NOT_RIGHT);
        }
    }

    return session.success();
}
