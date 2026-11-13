const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const remielle = @import("remielle.zig");
const Command = remielle.Command;
const protobuf = remielle.protobuf;
const Player = remielle.Player;

pub const Error = protobuf.DecodeError || Command.EncodeError;

pub fn Typed(comptime message_name_literal: @EnumLiteral()) type {
    const message_name = @tagName(message_name_literal);

    const response_name =
        message_name[0 .. message_name.len - request_suffix.len] ++
        response_suffix;

    return *extern struct {
        sink: Sink,
        player: *Player,
        time: *const Time,
        command: *const Command,
        conf: *const remielle.Configuration,

        comptime {
            assert(@sizeOf(TypedSession) == @sizeOf(TypeErased));
            assert(@alignOf(TypedSession) == @alignOf(TypeErased));
        }

        const TypedSession = @This();

        pub const DecodedBody = @field(protobuf.gen, message_name).Decoded;

        pub fn decodeBody(session: *TypedSession) protobuf.DecodeError!DecodedBody {
            return session.command.decodeBody(DecodedBody);
        }

        pub const Response = @field(protobuf.gen, response_name);

        pub fn respond(session: *TypedSession, rsp: Response) Sink.Error!void {
            const type_erased = session.typeErased();
            try type_erased.notify();

            return session.sink.respond(Response, &rsp);
        }

        pub fn notify(
            session: *TypedSession,
            comptime Notify: type,
            ntf: Notify,
        ) Sink.Error!void {
            return session.sink.notify(Notify, &ntf);
        }

        /// Sends a response with an erroneous retcode.
        /// Since this implies a failure, state synchronization notifications won't be sent to client.
        pub fn fail(session: *TypedSession, retcode: protobuf.Retcode) Sink.Error!void {
            assert(retcode != .RET_SUCC);
            return session.sink.respondMinimal(response_name, .{ .retcode = retcode });
        }

        /// Sends a response message with only a `retcode` field assigned.
        /// Preferred for the responses that don't carry additional data,
        /// as it avoids a dependency on the message type being defined.
        ///
        /// If an exact response message is *required*, `respond` should be used instead.
        pub fn success(session: *TypedSession) Sink.Error!void {
            const type_erased = session.typeErased();
            try type_erased.notify();

            return session.sink.respondMinimal(response_name, .{ .retcode = .RET_SUCC });
        }

        fn typeErased(session: *TypedSession) *TypeErased {
            return @ptrCast(session);
        }
    };
}

const request_suffix = "CsReq";
const response_suffix = "ScRsp";

pub const TypeErased = extern struct {
    sink: Sink,
    player: *Player,
    time: *const Time,
    command: *const Command,
    conf: *const remielle.Configuration,

    comptime {
        assert(std.meta.hasUniqueRepresentation(@This()));
    }

    fn notify(session: *TypeErased) Command.EncodeError!void {
        if (session.player.buildPlayerSyncScNotify()) |sync|
            try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &sync);

        if (session.player.buildEnterSceneScNotify()) |enter_scene|
            try session.sink.notify(protobuf.gen.EnterSceneScNotify, &enter_scene);

        if (session.player.buildHallRefresh()) |hall_refresh|
            try session.sink.notify(protobuf.gen.HallRefreshScNotify, &hall_refresh);
    }
};

pub const Time = struct {
    stamp: Io.Timestamp,
};

pub const Sink = extern struct {
    buffer_ptr: [*]u8,
    decrypt_vector: *const [4096]u8,
    packet_id_counter: *u32,
    buffer_len: u32,
    buffer_end: u32,
    ack_packet_id: u32,
    _: u32 = 0,

    comptime {
        assert(std.meta.hasUniqueRepresentation(@This()));
    }

    pub fn init(
        buffer: []u8,
        decrypt_vector: *const [4096]u8,
        packet_id_counter: *u32,
        ack_packet_id: u32,
    ) Sink {
        return .{
            .buffer_ptr = buffer.ptr,
            .buffer_len = @intCast(buffer.len),
            .buffer_end = 0,
            .decrypt_vector = decrypt_vector,
            .packet_id_counter = packet_id_counter,
            .ack_packet_id = ack_packet_id,
        };
    }

    pub fn unusedBufferSlice(sink: *Sink) []u8 {
        return sink.buffer_ptr[0..sink.buffer_len][sink.buffer_end..];
    }

    pub fn written(sink: *Sink) []u8 {
        assert(sink.buffer_end <= sink.buffer_len);
        return sink.buffer_ptr[0..sink.buffer_end];
    }

    pub const Error = Command.EncodeError;

    pub fn respond(sink: *Sink, comptime Body: type, body: *const Body) Sink.Error!void {
        const packet_id = sink.packet_id_counter.*;
        sink.packet_id_counter.* +%= 1;

        sink.buffer_end += try Command.encode(Body, body, .{
            .head = .{ .packet_id = packet_id, .ack_packet_id = sink.ack_packet_id },
            .buffer = sink.unusedBufferSlice(),
            .decrypt_vector = sink.decrypt_vector,
        });
    }

    pub fn notify(sink: *Sink, comptime Body: type, body: *const Body) Sink.Error!void {
        const packet_id = sink.packet_id_counter.*;
        sink.packet_id_counter.* +%= 1;

        sink.buffer_end += try Command.encode(Body, body, .{
            .head = .{ .packet_id = packet_id, .ack_packet_id = 0 },
            .buffer = sink.unusedBufferSlice(),
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
