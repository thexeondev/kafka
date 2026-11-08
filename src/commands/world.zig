const std = @import("std");

const kafka = @import("../kafka.zig");
const Player = kafka.Player;
const Session = kafka.Session;
const protobuf = kafka.protobuf;

pub fn EnterWorldCsReq(session: Session(.EnterWorldCsReq)) !void {
    session.player.enterMainCity();
    return session.respond(.{});
}

pub fn EnterSectionCompleteCsReq(session: Session(.EnterSectionCompleteCsReq)) !void {
    return session.respond(.{});
}

pub fn LeaveCurSceneCsReq(session: Session(.LeaveCurSceneCsReq)) !void {
    session.player.enterMainCity();
    return session.success();
}

pub fn EnterSectionCsReq(session: Session(.EnterSectionCsReq)) !void {
    const request = try session.decodeBody();
    const section = Player.MainCitySection.fromInt(request.section_id) orelse
        return session.fail(.RET_SCENE_NOT_FOUND);

    session.player.updateMainCitySection(section);
    return session.success();
}

pub fn ModMainCityTimeCsReq(session: Session(.ModMainCityTimeCsReq)) !void {
    const request = try session.decodeBody();

    const period_tag = std.enums.fromInt(protobuf.gen.TimePeriodType, request.time_period) orelse
        return session.fail(.RET_INVALID_REQUEST_DATA);

    const next_time_period_maybe: ?Player.TimePeriod = switch (period_tag) {
        .TimePeriodType_MORNING => .morning,
        .TimePeriodType_AFTERNOON => .afternoon,
        .TimePeriodType_EVENING => .evening,
        .TimePeriodType_NIGHT => .night,

        .TimePeriodType_NOW,
        .TimePeriodType_TIME_PERIOD_TYPE_NONE,
        => null,
    };

    if (next_time_period_maybe) |next_time_period| {
        const time_period_change = session.player.storage.time.period.fastForwardTo(next_time_period);
        session.player.updateTimePeriod(time_period_change);
    }

    return session.success();
}
