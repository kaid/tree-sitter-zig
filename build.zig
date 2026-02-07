const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "build-shared", "Build a shared library") orelse true;
    const reuse_alloc = b.option(bool, "reuse-allocator", "Reuse the library allocator") orelse false;

    const library_name = "tree-sitter-zig";

    const lib: *std.Build.Step.Compile = b.addLibrary(.{
        .name = library_name,
        .linkage = if (shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = if (shared) true else null,
        }),
    });

    lib.root_module.addCSourceFile(.{
        .file = b.path("src/parser.c"),
        .flags = &.{
            "-std=c11",
            "-fno-sanitize=undefined",
        },
    });
    if (fileExists(b, "src/scanner.c")) {
        lib.root_module.addCSourceFile(.{
            .file = b.path("src/scanner.c"),
            .flags = &.{
                "-std=c11",
                "-fno-sanitize=undefined",
            },
        });
    }

    if (reuse_alloc) {
        lib.root_module.addCMacro("TREE_SITTER_REUSE_ALLOCATOR", "");
    }
    if (optimize == .Debug) {
        lib.root_module.addCMacro("TREE_SITTER_DEBUG", "");
    }

    lib.root_module.addIncludePath(b.path("src"));

    b.installArtifact(lib);
    b.installFile("src/node-types.json", "node-types.json");

    if (fileExists(b, "queries")) {
        b.installDirectory(.{
            .source_dir = b.path("queries"),
            .install_dir = .prefix,
            .install_subdir = "queries",
            .include_extensions = &.{"scm"},
        });
    }

    const module = b.addModule(library_name, .{
        .root_source_file = b.path("bindings/zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bindings/zig/test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    tests.root_module.addImport(library_name, module);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    const fetch_deps = b.option(
        bool,
        "fetch-deps",
        "Fetch lazy dependencies required for running 'zig build test'",
    ) orelse false;

    const ts_dep: *std.Build.Dependency = blk: {
        if (b.lazyDependency("tree_sitter", .{})) |dep| break :blk dep;
        if (fetch_deps) break :blk b.dependency("tree_sitter", .{});

        const fail = std.Build.Step.Fail.create(
            b,
            "Lazy dependency 'tree_sitter' is not available.\n" ++
                "Re-run with: zig build -Dfetch-deps test\n",
        );
        test_step.dependOn(&fail.step);
        return;
    };

    const ts_lib = ts_dep.artifact("tree-sitter");
    tests.root_module.addIncludePath(ts_dep.path("lib/include"));
    tests.root_module.linkLibrary(ts_lib);
    test_step.dependOn(&run_tests.step);
    // const fetch_deps = b.option(
    //     bool,
    //     "fetch-deps",
    //     "Fetch lazy dependencies required for running 'zig build test'",
    // ) orelse false;
    // if (fetch_deps or dependencyAvailable(b, "tree_sitter")) {
    // } else {
    //     const fail = std.Build.Step.Fail.create(b,
    //         "Lazy dependency 'tree_sitter' is not available.\n" ++
    //             "Re-run with: zig build -Dfetch-deps test\n",
    //     );
    //     test_step.dependOn(&fail.step);
    // }
}

inline fn dependencyAvailable(b: *std.Build, name: []const u8) bool {
    const build_runner = @import("root");
    const deps = build_runner.dependencies;

    const pkg_hash = for (b.available_deps) |dep| {
        if (std.mem.eql(u8, dep[0], name)) break dep[1];
    } else return false;

    inline for (@typeInfo(deps.packages).@"struct".decls) |decl| {
        if (std.mem.eql(u8, decl.name, pkg_hash)) {
            const pkg = @field(deps.packages, decl.name);
            return !@hasDecl(pkg, "available") or pkg.available;
        }
    }

    return false;
}

inline fn fileExists(b: *std.Build, filename: []const u8) bool {
    const dir = b.build_root.handle;
    dir.access(b.graph.io, filename, .{}) catch return false;
    return true;
}
