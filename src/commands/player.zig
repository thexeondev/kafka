const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const Session = remielle.Session;
const protobuf = remielle.protobuf;

pub fn PlayerLoginCsReq(session: Session(.PlayerLoginCsReq)) !void {
    return session.respond(.{});
}

pub fn GetSelfBasicInfoCsReq(session: Session(.GetSelfBasicInfoCsReq)) !void {
    return session.respond(.{
        .self_basic_info = protobuf.pack.selfBasicInfo(&session.player.storage.role),
    });
}

pub fn GetServerTimestampCsReq(session: Session(.GetServerTimestampCsReq)) !void {
    return session.respond(.{
        .timestamp = @intCast(session.time.stamp.toMilliseconds()),
        .utc_offset = 3,
    });
}

pub fn KeepAliveNotify(_: Session(.KeepAliveNotify)) !void {}

pub fn ModAvatarCsReq(session: Session(.ModAvatarCsReq)) !void {
    const request = try session.decodeBody();
    const control_guise_avatar: Player.ControlGuiseAvatar = @fromBackingInt(request.control_guise_avatar_id);

    if (control_guise_avatar.requiresUnlock()) {
        if (!session.player.hasAvatarWithId(request.control_guise_avatar_id))
            return session.fail(.RET_AVATAR_PARAM_ERROR);
    }

    session.player.updateControlGuiseAvatar(control_guise_avatar);
    return session.success();
}
