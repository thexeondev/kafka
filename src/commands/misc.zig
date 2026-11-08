const kafka = @import("../kafka.zig");
const Session = kafka.Session;
const protobuf = kafka.protobuf;
const templates = kafka.templates;

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
                .show_post_girl_id_list = &.{3500001},
                .post_girl_item_list = &.{.{ .id = 3500001 }},
            },
            .business_card = .{},
            .player_accessory = .{
                .control_guise_avatar_id = @backingInt(session.any.player.storage.role.control_guise_avatar),
            },
        },
    });
}
