const Configuration = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const remielle = @import("remielle.zig");
const fatal = remielle.cli.fatal;

pub const defaults: Configuration = @import("defaults/remielle.zon");

version: Version,
hadal: Hadal,
client_secret_key: []const u8,
gateway_initial_decrypt_vector: *const [4096]u8,

pub const Version = struct {
    tag: []const u8,
    cdn: Cdn,

    pub const Cdn = struct {
        hotfix: Hotfix,
        audio_overlay: ?AudioOverlay = null,

        pub const Hotfix = struct {
            design_data: struct {
                base_url: []const u8,
                data_revision: []const u8,
                md5_files: []const u8,
            },
            game_res: struct {
                audio_revision: []const u8,
                base_url: []const u8,
                branch: []const u8,
                md5_files: []const u8,
                res_revision: []const u8,
            },
            silence_data: struct {
                base_url: []const u8,
                md5_files: []const u8,
                silence_revision: []const u8,
            },
        };

        pub const AudioOverlay = struct {
            upstream_url_prefix_original: []const u8,
            upstream_url_overlay: []const u8,
            directory_overlayed: []const u8,
            base_revision_original: []const u8,
            base_revision_overlayed: []const u8,
            last_revision_original: []const u8,
            last_revision_overlayed: []const u8,
            audio_version_size: u64,
            audio_version_md5: []const u8,
        };
    };
};

pub const Hadal = struct {
    zones: []const Zone,

    pub const Zone = struct {
        entrance: EntranceId,
        id: u32,
    };

    pub const EntranceId = enum(u32) {
        hadal_zone_scheduled_1 = 1,
        hadal_zone_stable = 2,
        hadal_zone_defensive = 3,
        hadal_zone_ambush = 4,
        boss_challenge_trial_1 = 9,
        boss_challenge_trial_2 = 10,
        boss_challenge_trial_3 = 11,
        hadal_zone_scheduled_2 = 13,
        hadal_zone_scheduled_3 = 14,
        boss_challenge_adversity_1 = 16,
        boss_challenge_adversity_2 = 17,
        boss_challenge_adversity_3 = 18,
        boss_challenge_adversity_4 = 19,
        free_training = 901,

        pub const count = @typeInfo(EntranceId).@"enum".field_names.len;
    };
};

pub const UpdateFromFileOptions = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for config contents.
    arena: Allocator,
    path_cwd_relative: []const u8,
    exit_if_not_found: bool,
};

pub fn updateFromFileOrExit(
    conf: *Configuration,
    io: Io,
    options: UpdateFromFileOptions,
) Io.Cancelable!void {
    const source = Io.Dir.cwd().readFileAllocOptions(
        io,
        options.path_cwd_relative,
        options.arena,
        .unlimited,
        .@"1",
        0,
    ) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => {
            if (!options.exit_if_not_found) return;
            fatal("config file {q} doesn't exist", .{options.path_cwd_relative});
        },
        else => fatal("failed to read {q}: {t}", .{ options.path_cwd_relative, err }),
    };

    var diag: std.zon.parse.Diagnostics = undefined;
    std.zon.parse.updateFromSlice(Configuration, conf, .{
        .gpa = options.gpa,
        .arena = options.arena,
        .source = source,
        .diagnostics = &diag,
        .ignore_unknown_fields = false,
    }) catch |err| switch (err) {
        error.ParseZon => fatal("{f}", .{diag.fmt(options.path_cwd_relative)}),
        error.OutOfMemory => fatal(
            "parsing file {q} caused out of memory",
            .{options.path_cwd_relative},
        ),
    };
}
