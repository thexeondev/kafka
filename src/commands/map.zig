const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

const remielle = @import("../remielle.zig");
const assets = remielle.assets;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn GetAreaMapDataCsReq(session: Session(.GetAreaMapDataCsReq)) !void {
    var groups_buffer: [
        templates.UrbanAreaMapGroup.table.count +
            templates.BigScenePortal.table.count
    ]protobuf.gen.AreaGroupInfo =
        undefined;
    var groups: ArrayList(protobuf.gen.AreaGroupInfo) = .initBuffer(&groups_buffer);

    for (templates.UrbanAreaMapGroup.table.items(.id)) |id| {
        groups.appendAssumeCapacity(.{
            .group_id = id,
            .area_progress = 99,
            .is_unlocked = true,
        });
    }

    for (templates.BigScenePortal.table.items(.area_id)) |id| {
        groups.appendAssumeCapacity(.{
            .group_id = id,
            .area_progress = 99,
            .is_unlocked = true,
        });
    }

    var streets_buffer: [
        templates.UrbanAreaMap.table.count +
            templates.BigScenePortal.table.count
    ]protobuf.gen.AreaStreetInfo =
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

    for (templates.BigScenePortal.table.items(.area_id)) |id| {
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

pub fn GetFloorBlockedGroupListCsReq(session: Session(.GetFloorBlockedGroupListCsReq)) !void {
    return session.respond(.{});
}

pub fn GetFloorActiveGroupListCsReq(session: Session(.GetFloorActiveGroupListCsReq)) !void {
    const request = try session.decodeBody();
    const floor = assets.Floor.table.get(request.floor_id) orelse
        return session.respond(.{});

    var group_ids_buffer: [assets.Group.table.group_ids.len]u32 = undefined;
    var group_ids: ArrayList(u32) = .initBuffer(&group_ids_buffer);

    for (floor.group_id_list) |group_id| {
        group_ids.appendAssumeCapacity(group_id);
    }

    return session.respond(.{ .group_id_list = group_ids.items });
}

pub fn GetFloorGroupMemberListCsReq(session: Session(.GetFloorGroupMemberListCsReq)) !void {
    const log = std.log.scoped(.GetFloorGroupMemberListCsReq);

    const request = try session.decodeBody();
    const floor = assets.Floor.table.get(request.floor_id) orelse {
        log.debug("requested floor {d} doesn't exist", .{request.floor_id});
        return session.respond(.{});
    };

    var members_buffer: [assets.Group.table.gadget_ids.len]protobuf.gen.GroupMemberId = undefined;
    var member_list: ArrayList(protobuf.gen.GroupMemberId) = .initBuffer(&members_buffer);

    for (floor.group_id_list) |group_id| {
        const group = assets.Group.table.getGroupById(group_id).?;

        for (group.gadget_types, group.gadget_config_ids) |gadget_type, config_id| {
            if (gadget_type == .portal) {
                member_list.appendAssumeCapacity(.{
                    .group_id = group_id,
                    .config_id = config_id,
                });
            }
        }
    }

    return session.respond(.{ .active_group_member_list = member_list.items });
}
