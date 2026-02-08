const std = @import("std");

pub fn build(b: *std.Build) void {
    {
        const target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const exe = b.addExecutable(.{
            .name = "xitlog",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lib.zig"),
                .target = target,
                .optimize = .ReleaseSmall,
            }),
        });
        exe.root_module.addImport("xitui", b.dependency("xitui", .{}).module("xitui"));

        exe.global_base = 6560;
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.import_memory = false;
        exe.export_memory = true;
        exe.stack_size = std.wasm.page_size;

        const number_of_pages = 16;
        exe.initial_memory = std.wasm.page_size * number_of_pages;
        exe.max_memory = std.wasm.page_size * number_of_pages;

        b.installArtifact(exe);
    }

    const xitlog = b.addModule("xitlog", .{
        .root_source_file = b.path("src/lib.zig"),
    });
    xitlog.addImport("xitui", b.dependency("xitui", .{}).module("xitui"));

    {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

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
