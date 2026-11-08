const kafka = @import("../kafka.zig");
const Player = kafka.Player;
const Session = kafka.Session;
const protobuf = kafka.protobuf;

pub fn PlayerLoginCsReq(session: Session(.PlayerLoginCsReq)) !void {
    return session.respond(.{});
}

pub fn GetSelfBasicInfoCsReq(session: Session(.GetSelfBasicInfoCsReq)) !void {
    return session.respond(.{
        .self_basic_info = protobuf.pack.selfBasicInfo(&session.any.player.storage.role),
    });
}

pub fn GetServerTimestampCsReq(session: Session(.GetServerTimestampCsReq)) !void {
    return session.respond(.{
        .timestamp = @intCast(session.any.time.toMilliseconds()),
        .utc_offset = 3,
    });
}

pub fn KeepAliveNotify(_: Session(.KeepAliveNotify)) !void {}

pub fn ModAvatarCsReq(session: Session(.ModAvatarCsReq)) !void {
    const request = try session.decodeBody();
    const control_guise_avatar: Player.ControlGuiseAvatar = @fromBackingInt(request.control_guise_avatar_id);

    if (control_guise_avatar.requiresUnlock()) {
        if (!session.any.player.hasAvatarWithId(request.control_guise_avatar_id))
            return session.fail(.RET_AVATAR_PARAM_ERROR);
    }

    session.any.player.updateControlGuiseAvatar(control_guise_avatar);
    return session.success();
}
