const std = @import("std");

const kafka = @import("../kafka.zig");
const Player = kafka.Player;
const Session = kafka.Session;
const protobuf = kafka.protobuf;
const Configuration = kafka.Configuration;

pub fn GetHadalZoneDataCsReq(session: Session(.GetHadalZoneDataCsReq)) !void {
    var hadal_entrance_list: protobuf.pack.HadalEntranceList = .empty;

    for (session.conf.hadal.zones) |*zone_conf| {
        protobuf.pack.hadalEntrance(hadal_entrance_list.addOneAssumeCapacity(), .{
            .entrance_type = switch (zone_conf.entrance) {
                .hadal_zone_stable, .hadal_zone_defensive => 1, // CONSTANT
                else => 2, // SCHEDULED
            },
            .entrance_id = @backingInt(zone_conf.entrance),
            .zone_id = zone_conf.id,
            .begin_timestamp = switch (zone_conf.entrance) {
                .hadal_zone_stable, .hadal_zone_defensive => 0,
                else => session.time.stamp.toSeconds() - 3600 * 24,
            },
            .end_timestamp = switch (zone_conf.entrance) {
                .hadal_zone_stable, .hadal_zone_defensive => 0,
                else => session.time.stamp.toSeconds() + 3600 * 24,
            },
        });
    }

    return session.respond(.{
        .hadal_entrance_list = hadal_entrance_list.items(.info),
    });
}
