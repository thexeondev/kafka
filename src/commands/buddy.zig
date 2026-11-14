const std = @import("std");

const remielle = @import("../remielle.zig");
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn GetBuddyDataCsReq(session: Session(.GetBuddyDataCsReq)) !void {
    var buddy_list_buffer: [templates.BuddyBase.table.count]protobuf.gen.BuddyInfo = undefined;

    return session.respond(.{
        .buddy_list = protobuf.pack.buddyList(&buddy_list_buffer),
    });
}
