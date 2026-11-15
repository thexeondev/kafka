const remielle = @import("../remielle.zig");
const Player = remielle.Player;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn PlayerLoginCsReq(session: Session(.PlayerLoginCsReq)) !void {
    return session.respond(.{});
}

pub fn GetSelfBasicInfoCsReq(session: Session(.GetSelfBasicInfoCsReq)) !void {
    return session.respond(.{
        .self_basic_info = protobuf.pack.selfBasicInfo(session.player),
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

    const guise_id = request.control_guise_avatar_id;
    const avatar_id = if (templates.AvatarForm.table.getByKey(guise_id)) |form| form: {
        break :form form.avatar_id;
    } else guise_id;

    if (!Player.isMainAvatar(avatar_id) and !session.player.hasAvatarWithId(avatar_id)) {
        return session.fail(.RET_AVATAR_PARAM_ERROR);
    }

    session.player.updateControlGuiseAvatar(@fromBackingInt(avatar_id));
    return session.success();
}
