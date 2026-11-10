const std = @import("std");
const assert = std.debug.assert;

const kafka = @import("kafka.zig");
const Session = kafka.Session;
const protobuf = kafka.protobuf;

const log = std.log.scoped(.@"kafka::commands");

const namespaces: []const type = &.{
    @import("commands/player.zig"),
    @import("commands/avatar.zig"),
    @import("commands/item.zig"),
    @import("commands/quest.zig"),
    @import("commands/misc.zig"),
    @import("commands/world.zig"),
    @import("commands/map.zig"),
    @import("commands/hadal_zone.zig"),
};

const HandlerFn = *const fn (*kafka.session.TypeErased) kafka.session.Error!void;

const cmd_count: usize = 10_000;
const handlers: *const [cmd_count]?HandlerFn = handlers: {
    var array: [cmd_count]?HandlerFn = @splat(null);
    for (namespaces) |namespace| {
        for (@typeInfo(namespace).@"struct".decl_names) |decl_name| {
            if (!@hasDecl(protobuf.gen, decl_name)) continue;

            const cmd_id = @field(protobuf.gen, decl_name).cmd_id;
            if (array[cmd_id] != null) @compileError("duplicated handler for " ++ decl_name);

            const Fn = @TypeOf(@field(namespace, decl_name));
            const fn_params = @typeInfo(Fn).@"fn".param_types;
            assert(fn_params.len == 1);
            assert(@typeInfo(fn_params[0].?) == .pointer);

            array[cmd_id] = @ptrCast(&@field(namespace, decl_name));
        }
    }

    const final = array;
    break :handlers &final;
};

pub const ExecuteError = kafka.session.Error || error{CommandIdIllegal};

pub fn execute(session: *kafka.session.TypeErased) ExecuteError!void {
    if (session.command.id >= cmd_count) return error.CommandIdIllegal;

    if (handlers[session.command.id]) |handlerFn| {
        try handlerFn(session);
    } else if (session.sink.ack_packet_id != 0) {
        log.debug("unhandled command id: {d}", .{session.command.id});
        try session.sink.respond(protobuf.gen.DummyScRsp, &.{});
    }
}
