const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const nimble = builder.dependency("nimble", .{});
    const nimble_module = nimble.module("nimble");

    const wisp = builder.dependency("wisp", .{});
    const wisp_module = wisp.module("wisp");

    const win32 = builder.dependency("zigwin32", .{});
    const win32_module = win32.module("win32");

    const wca = builder.dependency("wca", .{});
    const wca_module = wca.module("wca");

    const mute_resource = builder.addSystemCommand(&[_][]const u8{
        "windres",
        "-i",
        "mute.rc",
        "-o",
        "mute.res",
        "--input-format=rc",
        "--output-format=coff",
    });

    const deafen_resource = builder.addSystemCommand(&[_][]const u8{
        "windres",
        "-i",
        "deafen.rc",
        "-o",
        "deafen.res",
        "--input-format=rc",
        "--output-format=coff",
    });

    const mute = builder.addExecutable(.{
        .name = "mute",
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/mute.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nimble", .module = nimble_module },
                .{ .name = "wca", .module = wca_module },
                .{ .name = "win32", .module = win32_module },
                .{ .name = "wisp", .module = wisp_module },
            },
        }),
    });

    mute.root_module.addObjectFile(builder.path("mute.res"));
    mute.step.dependOn(&mute_resource.step);

    mute.root_module.link_libc = true;
    mute.root_module.linkSystemLibrary("user32", .{});
    mute.root_module.linkSystemLibrary("gdi32", .{});
    mute.root_module.linkSystemLibrary("gdiplus", .{});
    mute.root_module.linkSystemLibrary("msimg32", .{});
    mute.root_module.linkSystemLibrary("shell32", .{});
    mute.root_module.linkSystemLibrary("ole32", .{});

    mute.subsystem = .Windows;

    builder.installArtifact(mute);

    const deafen = builder.addExecutable(.{
        .name = "deafen",
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/deafen.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nimble", .module = nimble_module },
                .{ .name = "wca", .module = wca_module },
                .{ .name = "win32", .module = win32_module },
                .{ .name = "wisp", .module = wisp_module },
            },
        }),
    });

    deafen.root_module.addObjectFile(builder.path("deafen.res"));
    deafen.step.dependOn(&deafen_resource.step);

    deafen.root_module.link_libc = true;
    deafen.root_module.linkSystemLibrary("user32", .{});
    deafen.root_module.linkSystemLibrary("gdi32", .{});
    deafen.root_module.linkSystemLibrary("gdiplus", .{});
    deafen.root_module.linkSystemLibrary("msimg32", .{});
    deafen.root_module.linkSystemLibrary("shell32", .{});
    deafen.root_module.linkSystemLibrary("ole32", .{});

    deafen.subsystem = .Windows;

    builder.installArtifact(deafen);

    const test_module = builder.createModule(.{
        .root_source_file = builder.path("src/mute.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nimble", .module = nimble_module },
            .{ .name = "wca", .module = wca_module },
            .{ .name = "win32", .module = win32_module },
            .{ .name = "wisp", .module = wisp_module },
        },
    });

    test_module.link_libc = true;
    test_module.linkSystemLibrary("user32", .{});
    test_module.linkSystemLibrary("gdi32", .{});
    test_module.linkSystemLibrary("gdiplus", .{});
    test_module.linkSystemLibrary("msimg32", .{});
    test_module.linkSystemLibrary("shell32", .{});
    test_module.linkSystemLibrary("ole32", .{});

    const unit_test = builder.addTest(.{
        .root_module = test_module,
    });

    const run_test = builder.addRunArtifact(unit_test);

    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
