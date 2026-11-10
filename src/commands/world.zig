const std = @import("std");

const kafka = @import("../kafka.zig");
const Player = kafka.Player;
const Session = kafka.Session;
const protobuf = kafka.protobuf;
const StaticIntMap = kafka.StaticIntMap;

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

    var action_buffer: [1024]u8 = undefined;

    const action: protobuf.gen.ActionInfo =
        if (UiPage.by_interact_id.get(request.interact_id)) |page| open_ui: {
            break :open_ui .{
                .action_type = .OPEN_UI,
                .body = try encodeAction(protobuf.gen.ActionOpenUi, &action_buffer, .{
                    .ui = page.name,
                    .store_template_id = page.store_id,
                }),
            };
        } else if (SectionSwitch.by_interact_id.get(request.interact_id)) |section| section: {
            break :section .{
                .action_type = .SWITCH_SECTION,
                .body = try encodeAction(protobuf.gen.ActionSwitchSection, &action_buffer, .{
                    .section = section.id,
                    .transform_id = section.transform,
                }),
            };
        } else if (teleport_ui_interacts.get(request.interact_id) != null) teleport_ui: {
            break :teleport_ui .{
                .action_type = .SHOW_TELEPORT_UI,
                .body = try encodeAction(protobuf.gen.ActionShowTeleportUi, &action_buffer, .{}),
            };
        } else fallback: {
            log.debug("unhandled interact: {d}", .{request.interact_id});
            break :fallback .{
                .action_type = .SHOW_TIP,
                .body = try encodeAction(protobuf.gen.ConfigShowTip, &action_buffer, .{
                    .tip_id = 999200027,
                }),
            };
        };

    try session.notify(protobuf.gen.SectionEventScNotify, .{
        .section_id = @backingInt(session.player.storage.main_city.section),
        .action_list = &.{action},
    });

    return session.success();
}

const UiPage = struct {
    store_id: u32,
    name: []const u8,

    const by_interact_id: StaticIntMap(i32, UiPage) = .initComptime(&.{
        .{ 15001405, .{ .store_id = 1141, .name = "UIMusicPlayerPageController" } },
        .{ 10000009, .{ .store_id = 1161, .name = "UIYorozuyaPage" } },
        .{ 10000010, .{ .store_id = 1191, .name = "UIMainStoryPage" } },
        .{ 10000013, .{ .store_id = 1011, .name = "UIRamenStorePageController" } },
        .{ 10000024, .{ .store_id = 1021, .name = "UICafePageController" } },
        .{ 15000602, .{ .store_id = 1022, .name = "UICafePageController" } },
        .{ 10000028, .{ .store_id = 1031, .name = "UIBangbooModGaragePageController" } },
        .{ 15000301, .{ .store_id = 1061, .name = "UINewsStandPageController" } },
        .{ 15000302, .{ .store_id = 1062, .name = "UINewsStandPageController" } },
        .{ 15000401, .{ .store_id = 1071, .name = "UITrendyStorePageController" } },
        .{ 15001103, .{ .store_id = 2002, .name = "UIBattlePortal_HadalZonePageController" } },
        .{ 15001111, .{ .store_id = 2016, .name = "UIBattlePortal_HadalZoneV2PageController" } },
        .{ 15001106, .{ .store_id = 2010, .name = "UIMainCityTelescopePageController" } },
    });
};

const SectionSwitch = struct {
    id: u32,
    transform: []const u8,

    const by_interact_id: StaticIntMap(i32, SectionSwitch) = .initComptime(&.{
        .{ 10000001, .{ .id = 2, .transform = "Workshop_PlayerPos_FromStreet" } },
        .{ 10000002, .{ .id = 3, .transform = "Garage_PlayerPos_FromStreet" } },
        .{ 10000003, .{ .id = 1, .transform = "Street_PlayerPos_FromWorkshop" } },
        .{ 10000004, .{ .id = 3, .transform = "Garage_PlayerPos_FromWorkshop" } },
        .{ 10000005, .{ .id = 1, .transform = "Street_PlayerPos_FromGarage" } },
        .{ 10000006, .{ .id = 2, .transform = "Workshop_PlayerPos_FromGarage" } },
        .{ 10000016, .{ .id = 3, .transform = "Garage_PlayerPos_FromStreet2" } },
        .{ 10000017, .{ .id = 1, .transform = "Street_PlayerPos_FromGarage2" } },
        .{ 15001702, .{ .id = 103, .transform = "FortuneHIA_PlayerPos_Default" } },
        .{ 15001303, .{ .id = 101, .transform = "FortuneSquare_PlayerPos_ToHIA01" } },
    });
};

const teleport_ui_interacts: StaticIntMap(i32, void) = .initComptime(&.{
    .{ 10000021, {} },
});

pub fn SectionRefreshCsReq(session: Session(.SectionRefreshScRsp)) !void {
    return session.respond(.{});
}
