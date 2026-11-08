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

fn encodeAction(comptime Action: type, buffer: []u8, action: Action) ![]u8 {
    var writer: std.Io.Writer = .fixed(buffer);
    protobuf.encode(Action, &action, &writer) catch |err| switch (err) {
        error.WriteFailed => {
            std.log.err("failed to encode action of type " ++ Action.message_name, .{});
            return error.EncodeBufferExceeded;
        },
    };

    return writer.buffered();
}

pub fn InteractWithUnitCsReq(session: Session(.InteractWithUnitCsReq)) !void {
    const log = std.log.scoped(.InteractWithUnitCsReq);

    const request = try session.decodeBody();
    log.debug("unhandled interact: {d}", .{request.interact_id});

    var action_buffer: [1024]u8 = undefined;

    const fallback: protobuf.gen.ActionInfo = .{
        .action_type = .SHOW_TIP,
        .body = try encodeAction(protobuf.gen.ConfigShowTip, &action_buffer, .{
            .tip_id = 999200027,
        }),
    };

    try session.notify(protobuf.gen.SectionEventScNotify, .{
        .section_id = @backingInt(session.player.storage.main_city.section),
        .action_list = &.{fallback},
    });

    return session.success();
}
