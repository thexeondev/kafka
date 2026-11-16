const std = @import("std");
const Io = std.Io;
const process = std.process;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const hasUniqueRepresentation = std.meta.hasUniqueRepresentation;

pub fn main(init: process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        process.fatal("usage: remielle-convert-levelworld [input-dir] [output-dir]", .{});
    }

    const io = init.io;
    const dirs: Dirs = .{
        .input = try Io.Dir.cwd().openDir(io, args[1], .{}),
        .output = try Io.Dir.cwd().openDir(io, args[2], .{}),
    };

    const gpa = init.gpa;
    try convertConfigFloor(io, gpa, dirs);
    try convertConfigGroups(io, gpa, dirs);
}

const Dirs = struct {
    input: Io.Dir,
    output: Io.Dir,
};

const ConfigFloorJson = struct {
    data: []const Item,

    const Item = struct {
        floor_id: u32,
        floor_md5: []const u8,
        group_id_list: []const u32,
    };
};

fn parseJsonFile(
    comptime T: type,
    io: Io,
    gpa: Allocator,
    dir: Io.Dir,
    sub_path: []const u8,
) !std.json.Parsed(T) {
    const file = try dir.openFile(io, sub_path, .{});
    defer file.close(io);

    var file_read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &file_read_buffer);
    var json_reader: std.json.Reader = .init(gpa, &file_reader.interface);
    defer json_reader.deinit();

    return std.json.parseFromTokenSource(T, gpa, &json_reader, .{
        .ignore_unknown_fields = true,
    });
}

const ConfigFloorHeader = extern struct {
    floor_count: u32,
    ids_offset: u32,
    metadata_offset: u32,
    group_ids_offset: u32,
    strings_offset: u32,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }
};

const Slice = extern struct {
    offset: u32,
    len: u32,
};

const FloorMetadata = extern struct {
    group_id_list: Slice,
    floor_md5: Slice,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }
};

fn Table(comptime T: type) type {
    return struct {
        list: ArrayList(T),

        pub const init: @This() = .{ .list = .empty };

        pub fn putOne(table: *@This(), gpa: Allocator, item: T) Allocator.Error!void {
            _ = try table.put(gpa, &.{item});
        }

        pub fn put(table: *@This(), gpa: Allocator, items: []const T) Allocator.Error!Slice {
            const offset: u32 = @intCast(table.list.items.len);
            try table.list.appendSlice(gpa, items);

            return .{ .offset = offset, .len = @intCast(items.len) };
        }

        pub fn deinit(table: *@This(), gpa: Allocator) void {
            table.list.deinit(gpa);
        }

        pub fn itemCount(table: *const @This()) u32 {
            return @intCast(table.list.items.len);
        }

        pub fn byteCount(table: *const @This()) u32 {
            const bytes: []const u8 = @ptrCast(table.list.items);
            return @intCast(bytes.len);
        }

        pub fn byteSlice(table: *const @This()) []const u8 {
            return @ptrCast(table.list.items);
        }
    };
}

fn convertConfigFloor(io: Io, gpa: Allocator, dirs: Dirs) !void {
    const config_floor = try parseJsonFile(ConfigFloorJson, io, gpa, dirs.input, "ConfigFloor.json");
    defer config_floor.deinit();

    var floor_ids: Table(u32) = .init;
    defer floor_ids.deinit(gpa);

    var metadata: Table(FloorMetadata) = .init;
    defer metadata.deinit(gpa);

    var group_ids: Table(u32) = .init;
    defer group_ids.deinit(gpa);

    var strings: Table(u8) = .init;
    defer strings.deinit(gpa);

    for (config_floor.value.data) |floor| {
        _ = try floor_ids.put(gpa, &.{floor.floor_id});
        _ = try metadata.put(gpa, &.{.{
            .group_id_list = try group_ids.put(gpa, floor.group_id_list),
            .floor_md5 = try strings.put(gpa, floor.floor_md5),
        }});
    }

    const floor_count = floor_ids.itemCount();
    const metadata_offset: u32 = @sizeOf(ConfigFloorHeader);
    const ids_offset = metadata_offset + metadata.byteCount();
    const group_ids_offset = ids_offset + floor_ids.byteCount();
    const strings_offset = group_ids_offset + group_ids.byteCount();

    const header: ConfigFloorHeader = .{
        .floor_count = floor_count,
        .metadata_offset = metadata_offset,
        .ids_offset = ids_offset,
        .group_ids_offset = group_ids_offset,
        .strings_offset = strings_offset,
    };

    var vec: [5][]const u8 = .{
        @ptrCast(&header),
        metadata.byteSlice(),
        floor_ids.byteSlice(),
        group_ids.byteSlice(),
        strings.byteSlice(),
    };
    try writeVecToFile(io, dirs.output, "ConfigFloor.bin", &vec);
}

const ConfigGroupJson = struct {
    group_id: u32,
    members: []const Member,

    const Member = struct {
        config_id: u32,
        member_type: u8,
        gadget_server_metadata: ?struct {
            gadget_id: u32,
            gadget_type: u8,
        } = null,
    };
};

const ConfigGroupHeader = extern struct {
    group_count: u32,
    group_id_offset: u32,
    group_metadata_offset: u32,
    gadget_count: u32,
    gadget_ids_offset: u32,
    gadget_config_ids_offset: u32,
    gadget_types_offset: u32,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }
};

const GroupMetadata = extern struct {
    gadgets: Slice,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }
};

fn convertConfigGroups(io: Io, gpa: Allocator, dirs: Dirs) !void {
    var group_ids: Table(u32) = .init;
    defer group_ids.deinit(gpa);

    var group_metadata: Table(GroupMetadata) = .init;
    defer group_metadata.deinit(gpa);

    var gadget_ids: Table(u32) = .init;
    defer gadget_ids.deinit(gpa);

    var gadget_config_ids: Table(u32) = .init;
    defer gadget_config_ids.deinit(gpa);

    var gadget_types: Table(u8) = .init;
    defer gadget_types.deinit(gpa);

    const group_dir = try dirs.input.openDir(io, "ConfigGroup", .{ .iterate = true });
    defer group_dir.close(io);

    var group_dir_entries = group_dir.iterateAssumeFirstIteration();
    while (try group_dir_entries.next(io)) |entry| {
        if (entry.kind != .file) continue;

        const config_group = try parseJsonFile(ConfigGroupJson, io, gpa, group_dir, entry.name);
        defer config_group.deinit();

        const gadgets_offset = gadget_types.itemCount();
        for (config_group.value.members) |*member| {
            if (member.member_type != 1) continue;

            try gadget_config_ids.putOne(gpa, member.config_id);
            try gadget_ids.putOne(gpa, member.gadget_server_metadata.?.gadget_id);
            try gadget_types.putOne(gpa, member.gadget_server_metadata.?.gadget_type);
        }

        try group_ids.putOne(gpa, config_group.value.group_id);
        try group_metadata.putOne(gpa, .{
            .gadgets = .{
                .offset = gadgets_offset,
                .len = gadget_types.itemCount() - gadgets_offset,
            },
        });
    }

    const group_count = group_ids.itemCount();
    const group_id_offset = @sizeOf(ConfigGroupHeader);
    const group_metadata_offset = group_id_offset + group_ids.byteCount();
    const gadget_count = gadget_types.itemCount();
    const gadget_ids_offset = group_metadata_offset + group_metadata.byteCount();
    const gadget_config_ids_offset = gadget_ids_offset + gadget_ids.byteCount();
    const gadget_types_offset = gadget_config_ids_offset + gadget_config_ids.byteCount();

    const header: ConfigGroupHeader = .{
        .group_count = group_count,
        .group_id_offset = group_id_offset,
        .group_metadata_offset = group_metadata_offset,
        .gadget_count = gadget_count,
        .gadget_ids_offset = gadget_ids_offset,
        .gadget_config_ids_offset = gadget_config_ids_offset,
        .gadget_types_offset = gadget_types_offset,
    };

    var vec: [6][]const u8 = .{
        @ptrCast(&header),
        group_ids.byteSlice(),
        group_metadata.byteSlice(),
        gadget_ids.byteSlice(),
        gadget_config_ids.byteSlice(),
        gadget_types.byteSlice(),
    };
    try writeVecToFile(io, dirs.output, "ConfigGroup.bin", &vec);
}

fn writeVecToFile(io: Io, dir: Io.Dir, sub_path: []const u8, vec: [][]const u8) !void {
    const file = try dir.createFile(io, sub_path, .{});
    defer file.close(io);

    var file_write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_write_buffer);

    file_writer.interface.writeVecAll(vec) catch return file_writer.err.?;
    file_writer.interface.flush() catch return file_writer.err.?;
}
