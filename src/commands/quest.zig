const std = @import("std");

const kafka = @import("../kafka.zig");
const Player = kafka.Player;
const Session = kafka.Session;
const protobuf = kafka.protobuf;

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
    var avatars = session.any.player.avatars();
    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(avatar_info_list.addOneAssumeCapacity(), avatar);

    try session.notify(protobuf.gen.EnterSceneScNotify, .{
        .scene = .{
            .scene_type = 3,
            .scene_id = 19800014,
            .play_type = 290,
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
