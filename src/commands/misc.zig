const remielle = @import("../remielle.zig");
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn VideoGetInfoCsReq(session: Session(.VideoGetInfoCsReq)) !void {
    // TODO
    return session.respond(.{});
}

pub fn GetMiscDataCsReq(session: Session(.GetMiscDataCsReq)) !void {
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
                .control_guise_avatar_id = @backingInt(session.player.storage.role.control_guise_avatar),
            },
        },
    });
}
