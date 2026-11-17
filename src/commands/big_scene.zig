const std = @import("std");

const remielle = @import("../remielle.zig");
const assets = remielle.assets;
const Session = remielle.Session;
const protobuf = remielle.protobuf;

pub fn EnterFloorCsReq(session: Session(.EnterFloorCsReq)) !void {
    const log = std.log.scoped(.EnterFloorCsReq);

    const request = try session.decodeBody();
    const floor = assets.Floor.table.get(request.floor_id) orelse {
        log.debug("floor {d} doesn't exist", .{request.floor_id});
        return session.fail(.RET_FAIL);
    };

    const rollback_point = request.rollback_point orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    const pos = rollback_point.position orelse return session.fail(.RET_INVALID_REQUEST_DATA);
    const rot = rollback_point.rotation orelse return session.fail(.RET_INVALID_REQUEST_DATA);

    try session.notify(protobuf.gen.EnterFloorScNotify, .{
        .pos = .{ .x = pos.x, .y = pos.y, .z = pos.z },
        .floor_position = .{
            .player_position = .{ .x = pos.x, .y = pos.y, .z = pos.z },
            .player_rotation = .{ .x = rot.x, .y = rot.y, .z = rot.z },
        },
        .rollback_point = .{
            .name = rollback_point.name,
            .position = .{ .x = pos.x, .y = pos.y, .z = pos.z },
            .rotation = .{ .x = rot.x, .y = rot.y, .z = rot.z },
            .group_id = rollback_point.group_id,
        },
        .scene_id = floor.scene_config_id,
        .floor_id = request.floor_id,
        .day_of_week = @backingInt(session.player.storage.time.day),
        .time_in_minutes = session.player.storage.time.period.toMinutes(),
    });

    return session.success();
}
