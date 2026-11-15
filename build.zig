const std = @import("std");

const assert = std.debug.assert;

const format_paths = [_][]const u8{ "build.zig", "src" };

const Steps = struct {
    check: *std.Build.Step,
    ci: *std.Build.Step,
    run: *std.Build.Step,
    test_all: *std.Build.Step,
    test_fake: *std.Build.Step,
    test_fmt: *std.Build.Step,
    test_unit: *std.Build.Step,
};

const Context = struct {
    builder: *std.Build,
    filters: []const []const u8,
    optimize: std.lang.Optimize,
    steps: Steps,
    target: std.Build.ResolvedTarget,
};

const Program = struct {
    icon: []const u8,
    name: []const u8,
    resource: []const u8,
    root: []const u8,
};

const programs = [_]Program{
    .{ .icon = "assets/unmute.ico", .name = "mute", .resource = "mute.rc", .root = "src/mute.zig" },
    .{
        .icon = "assets/undeafen.ico",
        .name = "deafen",
        .resource = "deafen.rc",
        .root = "src/deafen.zig",
    },
};

const assets = [_][]const u8{
    "atlas_bold_small.a8",
    "atlas_regular_large.a8",
    "atlas_regular_small.a8",
    "deafen.rgba",
    "mute.rgba",
    "undeafen.rgba",
    "unmute.rgba",
};

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const filters = builder.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const context = Context{
        .builder = builder,
        .filters = filters,
        .optimize = optimize,
        .steps = .{
            .check = builder.step("check", "Compile every artifact without running it"),
            .ci = builder.step("ci", "Run every check and test"),
            .run = builder.step("run", "Build and run the capture application"),
            .test_all = builder.step("test", "Run every test suite and the format check"),
            .test_fake = builder.step(
                "test:fake",
                "Run the end to end tests against the fake libraries",
            ),
            .test_fmt = builder.step("test:fmt", "Check that every source file is formatted"),
            .test_unit = builder.step("test:unit", "Run the unit tests and the tidy check"),
        },
        .target = target,
    };

    add_executables(&context);
    add_unit_tests(&context);
    add_fake_tests(&context);
    add_cross_check(&context);
    add_format(&context);

    builder.getInstallStep().dependOn(context.steps.check);
}

fn add_executables(context: *const Context) void {
    const builder = context.builder;

    for (programs) |program| {
        const module = create_module(context, program.root);
        const exe = builder.addExecutable(.{ .name = program.name, .root_module = module });

        add_windows_resource(context, module, exe, program);

        builder.installArtifact(exe);

        context.steps.check.dependOn(&exe.step);

        if (!std.mem.eql(u8, program.name, programs[0].name)) {
            continue;
        }

        const run = builder.addRunArtifact(exe);

        run.step.dependOn(builder.getInstallStep());

        context.steps.run.dependOn(&run.step);
    }
}

fn add_unit_tests(context: *const Context) void {
    const builder = context.builder;
    const module = create_module(context, "src/unit_tests.zig");
    const unit = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(unit);

    run.has_side_effects = true;
    run.setCwd(builder.path("."));

    context.steps.test_unit.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&unit.step);
    context.steps.ci.dependOn(context.steps.test_unit);
}

fn add_fake_tests(context: *const Context) void {
    const builder = context.builder;
    const module = create_module(context, "src/scenario.zig");
    const fake = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(fake);

    context.steps.test_fake.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&fake.step);
    context.steps.ci.dependOn(context.steps.test_fake);
}

fn add_cross_check(context: *const Context) void {
    const builder = context.builder;

    const queries = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    };

    for (queries) |query| {
        if (query.os_tag.? == context.target.result.os.tag) {
            continue;
        }

        const resolved = builder.resolveTargetQuery(query);

        var scoped = context.*;

        scoped.target = resolved;

        for (programs) |program| {
            const module = create_module(&scoped, program.root);

            const exe = builder.addExecutable(.{
                .name = builder.fmt("{s}-{s}", .{ program.name, @tagName(query.os_tag.?) }),
                .root_module = module,
            });

            add_windows_resource(&scoped, module, exe, program);

            context.steps.check.dependOn(&exe.step);
        }
    }
}

fn add_format(context: *const Context) void {
    const builder = context.builder;
    const format = builder.addFmt(.{ .paths = builder.pathList(&format_paths), .check = true });

    context.steps.test_fmt.dependOn(&format.step);
    context.steps.test_all.dependOn(&format.step);
    context.steps.ci.dependOn(context.steps.test_fmt);
    context.steps.ci.dependOn(context.steps.check);
}

fn add_windows_resource(
    context: *const Context,
    module: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    program: Program,
) void {
    assert(std.mem.endsWith(u8, program.resource, ".rc"));
    assert(std.mem.endsWith(u8, program.icon, ".ico"));

    if (context.target.result.os.tag != .windows) {
        return;
    }

    exe.subsystem = .windows;

    const builder = context.builder;
    const name = builder.fmt("zig rc {s}", .{program.resource});
    const resource = std.Build.Step.Run.create(builder, name);

    resource.addFileArg2(.zig_exe, .{});

    resource.addArgs(&.{
        "rc",
        "/:auto-includes",
        "any",
        "/:output-format",
        "coff",
        "/:target",
        @tagName(context.target.result.cpu.arch),
        "--",
    });

    resource.addFileArg2(builder.path(program.resource), .{});
    resource.addFileInput(builder.path(program.icon));

    const object = resource.addOutputFileArg2(builder.fmt("{s}.obj", .{program.name}), .{});

    module.addObjectFile(object);
}

fn create_module(context: *const Context, root: []const u8) *std.Build.Module {
    assert(std.mem.startsWith(u8, root, "src/"));
    assert(std.mem.endsWith(u8, root, ".zig"));

    const builder = context.builder;

    const arc = builder.dependency("arc", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const kalymma = builder.dependency("kalymma", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const mantra = builder.dependency("mantra", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const nimble = builder.dependency("nimble", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const toml = builder.dependency("toml", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const umbra = builder.dependency("umbra", .{
        .target = context.target,
        .optimize = context.optimize,
    });

    const module = builder.createModule(.{
        .root_source_file = builder.path(root),
        .target = context.target,
        .optimize = context.optimize,
    });

    module.addImport("arc", arc.module("arc"));
    module.addImport("kalymma", kalymma.module("kalymma"));
    module.addImport("mantra", mantra.module("mantra"));
    module.addImport("nimble", nimble.module("nimble"));
    module.addImport("toml", toml.module("toml"));
    module.addImport("umbra", umbra.module("umbra"));

    for (assets) |asset| {
        module.addAnonymousImport(asset, .{
            .root_source_file = builder.path(builder.fmt("assets/{s}", .{asset})),
        });
    }

    return module;
}
