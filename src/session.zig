const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const kafka = @import("kafka.zig");
const Command = kafka.Command;
const protobuf = kafka.protobuf;
const Player = kafka.Player;

pub fn Session(comptime message_name_literal: @EnumLiteral()) type {
    return extern struct {
        any: *Any,

        const S = @This();

        const message_name = @tagName(message_name_literal);

        const response_name =
            message_name[0 .. message_name.len - request_suffix.len] ++
            response_suffix;

        const Response = @field(protobuf.gen, response_name);

        pub const DecodedBody = @field(protobuf.gen, message_name).Decoded;

        pub fn decodeBody(s: S) protobuf.DecodeError!DecodedBody {
            return s.any.command.decodeBody(DecodedBody);
        }

        pub fn respond(s: S, rsp: Response) Any.Sink.Error!void {
            try s.any.notify();
            return s.any.sink.respond(Response, &rsp);
        }

        pub fn notify(s: S, comptime Notify: type, ntf: Notify) Any.Sink.Error!void {
            return s.any.sink.notify(Notify, &ntf);
        }

        /// Sends a response with an erroneous retcode.
        /// Since this implies a failure, state synchronization notifications won't be sent to client.
        pub fn fail(s: S, retcode: protobuf.Retcode) Any.Sink.Error!void {
            assert(retcode != .RET_SUCC);
            return s.any.sink.respondMinimal(response_name, .{ .retcode = retcode });
        }

        /// Sends a response message with only a `retcode` field assigned.
        /// Preferred for the responses that don't carry additional data,
        /// as it avoids a dependency on the message type being defined.
        ///
        /// If an exact response message is *required*, `respond` should be used instead.
        pub fn success(s: S) Any.Sink.Error!void {
            try s.any.notify();
            return s.any.sink.respondMinimal(response_name, .{ .retcode = .RET_SUCC });
        }
    };
}

const request_suffix = "CsReq";
const response_suffix = "ScRsp";

pub const Any = struct {
    command: Command,
    player: Player,
    time: Io.Timestamp,
    sink: Sink,

    pub const Error = protobuf.DecodeError || Command.EncodeError;

    pub const Sink = struct {
        buffer: []u8,
        bytes_written: usize = 0,
        decrypt_vector: *const [4096]u8,

        packet_id_counter: *u32,
        ack_packet_id: u32,

        pub const Error = Command.EncodeError;

        pub fn respond(sink: *Sink, comptime Body: type, body: *const Body) Sink.Error!void {
            const packet_id = sink.packet_id_counter.*;
            sink.packet_id_counter.* +%= 1;

            sink.bytes_written += try Command.encode(Body, body, .{
                .head = .{ .packet_id = packet_id, .ack_packet_id = sink.ack_packet_id },
                .buffer = sink.buffer[sink.bytes_written..],
                .decrypt_vector = sink.decrypt_vector,
            });
        }

        pub fn notify(sink: *Sink, comptime Body: type, body: *const Body) Sink.Error!void {
            const packet_id = sink.packet_id_counter.*;
            sink.packet_id_counter.* +%= 1;

            sink.bytes_written += try Command.encode(Body, body, .{
                .head = .{ .packet_id = packet_id, .ack_packet_id = 0 },
                .buffer = sink.buffer[sink.bytes_written..],
                .decrypt_vector = sink.decrypt_vector,
            });
        }

        pub const RespondMinimalOptions = struct {
            retcode: protobuf.Retcode,
        };

        pub fn respondMinimal(
            sink: *Sink,
            comptime message_name: []const u8,
            options: RespondMinimalOptions,
        ) Sink.Error!void {
            const Message = if (@hasDecl(protobuf.gen, message_name))
                @field(protobuf.gen, message_name)
            else
                protobuf.gen.DummyScRsp;

            return respond(sink, Message, &.{ .retcode = @backingInt(options.retcode) });
        }
    };

    fn notify(any_session: *Any) Command.EncodeError!void {
        if (any_session.player.buildPlayerSyncScNotify()) |sync|
            try any_session.sink.notify(protobuf.gen.PlayerSyncScNotify, &sync);

        if (any_session.player.buildEnterSceneScNotify()) |enter_scene|
            try any_session.sink.notify(protobuf.gen.EnterSceneScNotify, &enter_scene);

        if (any_session.player.buildHallRefresh()) |hall_refresh|
            try any_session.sink.notify(protobuf.gen.HallRefreshScNotify, &hall_refresh);
    }
};
