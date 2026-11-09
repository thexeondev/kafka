const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Build = std.Build;

const zig_version: std.SemanticVersion = .{
    .major = 0,
    .minor = 17,
    .patch = 0,
};

comptime {
    const zig_version_equal =
        zig_version.major == builtin.zig_version.major and
        zig_version.minor == builtin.zig_version.minor and
        zig_version.patch == builtin.zig_version.patch;

    if (!zig_version_equal) @compileError(std.fmt.comptimePrint(
        "unsupported zig version: expected {f}, found {f}",
        .{ zig_version, builtin.zig_version },
    ));
}

const build_version: std.SemanticVersion = .{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

const template_dir_path = "assets/TemplateTb"; // Required asset.
const textmap_raw_path = "assets/TextMap_EnTemplateTb.bin"; // Optional asset.
const textmap_converted_path = "assets/textmap.bin"; // Required if `textmap_raw_path` is missing.

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("kafka", .{
        .root_source_file = b.path("src/kafka.zig"),
        .target = target,
        .optimize = optimize,
    });
    try convertTemplates(b, module);
    importFile(b, module, "defaults/kafka.zon");
    importFile(b, module, textmap_converted_path);

    const module_tests = b.addTest(.{ .root_module = module });
    const test_step = b.step("test", "run the tests");
    test_step.dependOn(&b.addRunArtifact(module_tests).step);

    const exe = b.addExecutable(.{
        .name = "kafka",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "kafka", .module = module }},
        }),
    });
    b.installArtifact(exe);

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);

    const version_string = collectVersionStringFromGit(b);
    exe_options.addOption([]const u8, "version", version_string);

    const run_exe = b.addRunArtifact(exe);
    run_exe.addPassthruArgs();
    b.step("serve", "start the server").dependOn(&run_exe.step);

    if (try maybeCompileProto(b)) |step| {
        exe.step.dependOn(step);
        module_tests.step.dependOn(step);
    }

    if (maybeConvertTextMap(b)) |step| {
        exe.step.dependOn(step);
        module_tests.step.dependOn(step);
    }
}

fn importFile(b: *Build, module: *Build.Module, path: []const u8) void {
    module.addAnonymousImport(path, .{ .root_source_file = b.path(path) });
}

fn maybeCompileProto(b: *Build) !?*Build.Step {
    b.root.access(b.graph.io, "proto", .{}) catch return null;
    b.dependOnDirectoryContents(b.path("proto"));

    const compiler = b.addExecutable(.{
        .name = "kafka-compile-proto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/compile-proto.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run = b.addRunArtifact(compiler);
    run.expectExitCode(0);

    const proto_dir = try b.root.openDir(b.graph.io, "proto", .{ .iterate = true });
    defer proto_dir.close(b.graph.io);

    var entries = proto_dir.iterateAssumeFirstIteration();
    while (try entries.next(b.graph.io)) |entry| {
        if (entry.kind != .file) continue;

        const path = b.fmt("proto/{s}", .{entry.name});
        run.addFileArg2(b.path(path), .{});
    }

    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(
        run.captureStdOut(.{ .basename = "generated.zig" }),
        "src/protobuf/generated.zig",
    );
    return &update.step;
}

fn maybeConvertTextMap(b: *Build) ?*Build.Step {
    b.root.access(b.graph.io, textmap_raw_path, .{ .read = true }) catch return null;

    const converter = b.addExecutable(.{
        .name = "kafka-convert-textmap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/convert-textmap.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const convert = b.addRunArtifact(converter);
    convert.expectExitCode(0);
    convert.addFileArg2(b.path(textmap_raw_path), .{});

    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(
        convert.captureStdOut(.{ .basename = "textmap.bin" }),
        textmap_converted_path,
    );
    return &update.step;
}

fn convertTemplates(b: *Build, kafka_module: *Build.Module) !void {
    b.dependOnDirectoryContents(b.path(template_dir_path));

    const converter = b.addExecutable(.{
        .name = "kafka-convert-templatetb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/convert-templatetb.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const convert = b.addRunArtifact(converter);
    convert.expectExitCode(0);
    convert.addDirectoryArg2(b.path(template_dir_path), .{});
    const converted_dir_path = convert.addOutputDirectoryArg2("TemplateTb", .{});

    var template_dir = try b.root.openDir(b.graph.io, template_dir_path, .{ .iterate = true });
    defer template_dir.close(b.graph.io);

    var template_dir_entries = template_dir.iterateAssumeFirstIteration();
    while (try template_dir_entries.next(b.graph.io)) |entry| {
        if (entry.kind != .file) continue;

        const converted_file_name = Io.Dir.path.stem(entry.name);
        const converted_file_path = converted_dir_path.path(b, converted_file_name);
        kafka_module.addAnonymousImport(converted_file_name, .{
            .root_source_file = converted_file_path,
        });

        convert.addFileInput(b.path(b.fmt("{s}/{s}", .{ template_dir_path, entry.name })));
    }
}

fn collectVersionStringFromGit(b: *Build) []const u8 {
    const version_string = b.fmt(
        "{d}.{d}.{d}",
        .{ build_version.major, build_version.minor, build_version.patch },
    );

    b.root.access(b.graph.io, ".git/logs/HEAD", .{ .read = true }) catch
        return version_string;

    b.dependOnFileMetadata(b.path(".git/logs/HEAD"));

    var code: u8 = undefined;
    const commit_height_untrimmed = b.runAllowFail(&[_][]const u8{
        "git",
        "-C", b.fmt("{f}", .{b.root}), // affects the --git-dir argument
        "--git-dir", ".git", // affected by the -C argument
        "rev-list", "--count", "HEAD", //
    }, &code, .ignore) catch return version_string;
    const commit_height = mem.trim(u8, commit_height_untrimmed, "\n\r");

    const commit_hash_untrimmed = b.runAllowFail(&[_][]const u8{
        "git",
        "-C", b.fmt("{f}", .{b.root}), // affects the --git-dir argument
        "--git-dir", ".git", // affected by the -C argument
        "rev-parse", "--short", "HEAD", //
    }, &code, .ignore) catch return version_string;
    const commit_hash = mem.trim(u8, commit_hash_untrimmed, "\n\r");

    return b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_hash });
}
