const remielle = @import("../remielle.zig");
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn VideoGetInfoCsReq(session: Session(.VideoGetInfoCsReq)) !void {
    // TODO
    return session.respond(.{});
}

pub fn GetMiscDataCsReq(session: Session(.GetMiscDataCsReq)) !void {
    const control_guise_avatar = session.player.storage.role.control_guise_avatar;
    const guise_skin_id = if (control_guise_avatar.toAvatarId()) |avatar_id| skin: {
        const avatar = session.player.getAvatarById(@backingInt(avatar_id)).?;
        break :skin avatar.skin_id_maybe orelse 0;
    } else 0;

    return session.respond(.{
        .data = .{
            .unlock = .{
                .unlocked_list = templates.UnlockConfig.table.items(.id),
            },
            .teleport = .{
                .unlocked_list = templates.TeleportConfig.table.items(.id),
            },
            .post_girl = .{
                .show_post_girl_id_list = &.{3510055},
                .post_girl_item_list = &.{.{ .id = 3510055 }},
            },
            .business_card = .{},
            .player_accessory = .{
                .control_guise_avatar_id = @backingInt(control_guise_avatar),
                .control_guise_avatar_skin_id = guise_skin_id,
            },
        },
    });
}
