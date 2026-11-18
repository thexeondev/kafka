const std = @import("std");
const ArrayList = std.ArrayList;

const remielle = @import("../remielle.zig");
const client = remielle.client;
const Player = remielle.Player;
const Session = remielle.Session;
const protobuf = remielle.protobuf;
const templates = remielle.templates;

pub fn VideoGetInfoCsReq(session: Session(.VideoGetInfoCsReq)) !void {
    // TODO
    return session.respond(.{});
}

pub fn GetSystemSettingsCsReq(session: Session(.GetSystemSettingsCsReq)) !void {
    const request = try session.decodeBody();
    const settings = &session.player.storage.system_settings;

    const keyboard_keymap_capacity = Player.Storage.SystemSettings.KeyboardKeymap.capacity;
    var keyboard_keymap_buffer: [keyboard_keymap_capacity]protobuf.KeyValue(u32, i32) = undefined;
    var keyboard_keymap: ArrayList(protobuf.KeyValue(u32, i32)) =
        .initBuffer(&keyboard_keymap_buffer);
    for (
        settings.keyboard_keymap.list.items(.input),
        settings.keyboard_keymap.list.items(.key),
    ) |input, key| {
        keyboard_keymap.appendAssumeCapacity(.{
            .key = @backingInt(input),
            .value = @backingInt(key),
        });
    }

    const mouse_keymap_capacity = Player.Storage.SystemSettings.MouseKeymap.capacity;
    var mouse_keymap_buffer: [mouse_keymap_capacity]protobuf.KeyValue(u32, i32) = undefined;
    var mouse_keymap: ArrayList(protobuf.KeyValue(u32, i32)) =
        .initBuffer(&mouse_keymap_buffer);
    for (
        settings.mouse_keymap.list.items(.input),
        settings.mouse_keymap.list.items(.key),
    ) |input, key| {
        mouse_keymap.appendAssumeCapacity(.{
            .key = @backingInt(input),
            .value = @backingInt(key),
        });
    }

    return session.respond(.{
        .type = request.type,
        .system_settings = .{
            .input_settings_map = &.{
                .{
                    .key = @backingInt(client.SettingsType.keyboard),
                    .value = .{ .input_key_map = keyboard_keymap.items },
                },
                .{
                    .key = @backingInt(client.SettingsType.mouse),
                    .value = .{ .input_key_map = mouse_keymap.items },
                },
            },
        },
    });
}

pub fn GetMiscDataCsReq(session: Session(.GetMiscDataCsReq)) !void {
    const control_guise_avatar_base = session.player.storage.role.control_guise_avatar;

    const guise_skin_id = if (control_guise_avatar_base.toAvatarId()) |avatar_id| skin: {
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
                .control_guise_avatar_id = session.player.getControlGuiseAvatarId(),
                .control_guise_avatar_skin_id = guise_skin_id,
            },
        },
    });
}

pub fn ModSystemSettingsCsReq(session: Session(.ModSystemSettingsCsReq)) !void {
    const log = std.log.scoped(.ModSystemSettingsCsReq);
    var request = try session.decodeBody();

    if (request.input_settings) |*input_settings| {
        const settings_type: client.SettingsType = @fromBackingInt(request.type);
        switch (settings_type) {
            _ => log.debug("unknown type: {d}", .{request.type}),
            .keyboard => {
                var keymap: Player.Storage.SystemSettings.KeyboardKeymap = .empty;
                while (try input_settings.input_key_map.next()) |kv| {
                    if (kv.value == -1) continue;

                    const input = std.enums.fromInt(client.LogicButtonInputType, kv.key) orelse
                        return session.fail(.RET_INVALID_REQUEST_DATA);

                    const key = std.enums.fromInt(client.KeyboardKey, kv.value) orelse
                        return session.fail(.RET_INVALID_REQUEST_DATA);

                    if (!keymap.put(key, input)) {
                        log.debug("duplicated keyboard keymap entry {any}", .{kv});
                        return session.fail(.RET_INVALID_REQUEST_DATA);
                    }
                }

                session.player.updateKeyboardKeymap(keymap);
            },
            .mouse => {
                var keymap: Player.Storage.SystemSettings.MouseKeymap = .empty;
                while (try input_settings.input_key_map.next()) |kv| {
                    if (kv.value == -1) continue;

                    const input = std.enums.fromInt(client.LogicButtonInputType, kv.key) orelse
                        return session.fail(.RET_INVALID_REQUEST_DATA);

                    const key = std.enums.fromInt(client.MouseButton, kv.value) orelse
                        return session.fail(.RET_INVALID_REQUEST_DATA);

                    if (!keymap.put(key, input)) {
                        log.debug("duplicated mouse keymap entry {any}", .{kv});
                        return session.fail(.RET_INVALID_REQUEST_DATA);
                    }
                }

                session.player.updateMouseKeymap(keymap);
            },
        }
    }

    return session.success();
}
