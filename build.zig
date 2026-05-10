const std = @import("std");

pub fn build(b: *std.Build) void {
    const xitlog = b.addModule("xitlog", .{
        .root_source_file = b.path("src/lib.zig"),
    });
    xitlog.addImport("xitui", b.dependency("xitui", .{}).module("xitui"));

    {
        const target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const exe = b.addExecutable(.{
            .name = "xitlog",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main_wasm.zig"),
                .target = target,
                .optimize = .ReleaseSmall,
            }),
        });
        exe.root_module.addImport("xitlog", xitlog);

        exe.global_base = 6560;
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.import_memory = false;
        exe.export_memory = true;
        exe.stack_size = std.wasm.page_size;

        const initial_pages = 16;
        const max_pages = 256;
        exe.initial_memory = std.wasm.page_size * initial_pages;
        exe.max_memory = std.wasm.page_size * max_pages;

        b.installArtifact(exe);
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    {
        const exe = b.addExecutable(.{
            .name = "xitlog",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main_term.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.root_module.addImport("xitlog", xitlog);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/test.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        unit_tests.root_module.addImport("xitlog", xitlog);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        run_unit_tests.has_side_effects = true;
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
