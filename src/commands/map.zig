const std = @import("std");
const ArrayList = std.ArrayList;

const remielle = @import("../remielle.zig");
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn GetAreaMapDataCsReq(session: Session(.GetAreaMapDataCsReq)) !void {
    var groups_buffer: [templates.UrbanAreaMapGroup.table.count]protobuf.gen.AreaGroupInfo =
        undefined;
    var groups: ArrayList(protobuf.gen.AreaGroupInfo) = .initBuffer(&groups_buffer);

    for (templates.UrbanAreaMapGroup.table.items(.id)) |id| {
        groups.appendAssumeCapacity(.{
            .group_id = id,
            .area_progress = 99,
            .is_unlocked = true,
        });
    }

    var streets_buffer: [templates.UrbanAreaMap.table.count]protobuf.gen.AreaStreetInfo =
        undefined;
    var streets: ArrayList(protobuf.gen.AreaStreetInfo) = .initBuffer(&streets_buffer);

    for (templates.UrbanAreaMap.table.items(.id)) |id| {
        streets.appendAssumeCapacity(.{
            .area_id = id,
            .area_progress = 99,
            .is_unlocked = true,
            .is_area_pop_show = true,
            .is_urban_area_show = true,
            .is_3d_area_show = true,
        });
    }

    return session.respond(.{ .data = .{
        .group = groups.items,
        .street = streets.items,
    } });
}

pub fn GetNewAreaPortalListCsReq(session: Session(.GetNewAreaPortalListCsReq)) !void {
    return session.respond(.{});
}

pub fn GetFloorActiveGroupListCsReq(session: Session(.GetFloorActiveGroupListCsReq)) !void {
    return session.respond(.{});
}
