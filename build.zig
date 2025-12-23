const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const toolkit = builder.dependency("toolkit", .{});
    const toolkit_module = toolkit.module("toolkit");

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
                .{ .name = "toolkit", .module = toolkit_module },
                .{ .name = "win32", .module = win32_module },
                .{ .name = "wca", .module = wca_module },
            },
        }),
    });

    mute.addObjectFile(builder.path("mute.res"));
    mute.step.dependOn(&mute_resource.step);

    mute.linkLibC();
    mute.linkSystemLibrary("user32");
    mute.linkSystemLibrary("gdi32");
    mute.linkSystemLibrary("shell32");
    mute.linkSystemLibrary("ole32");

    mute.subsystem = .Windows;

    builder.installArtifact(mute);

    const deafen = builder.addExecutable(.{
        .name = "deafen",
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/deafen.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "toolkit", .module = toolkit_module },
                .{ .name = "win32", .module = win32_module },
                .{ .name = "wca", .module = wca_module },
            },
        }),
    });

    deafen.addObjectFile(builder.path("deafen.res"));
    deafen.step.dependOn(&deafen_resource.step);

    deafen.linkLibC();
    deafen.linkSystemLibrary("user32");
    deafen.linkSystemLibrary("gdi32");
    deafen.linkSystemLibrary("shell32");
    deafen.linkSystemLibrary("ole32");

    deafen.subsystem = .Windows;

    builder.installArtifact(deafen);
}
