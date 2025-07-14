const std = @import("std");
const tree = @import("tree.zig");
pub fn main() !void {
    try parse_passed_arguments_form_command_line();
}
pub fn parse_passed_arguments_form_command_line() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var cwd = std.fs.cwd();
    defer cwd.close();

    const cwd_path = try cwd.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    var cwd_iterable = try std.fs.openDirAbsolute(cwd_path, .{ .iterate = true });
    defer cwd_iterable.close();

    if (args.len > 1) {
        const operation_name = args[1];

        if (std.mem.eql(u8, operation_name, "init")) {
            try init_repo(cwd);
        } else if (std.mem.eql(u8, operation_name, "commit")) {
            if (args.len < 3) {
                std.debug.print("ERR: please specify commit name", .{});
                return;
            }
            try commit(allocator, args[2], cwd_path, cwd_iterable);
        } else if (std.mem.eql(u8, operation_name, "clone")) {
            try clone_repo();
        }
    }
}
pub fn commit(allocator: std.mem.Allocator, commit_name: []u8, cwd_path: []u8, cwd_iterable: std.fs.Dir) !void {
    const base_path = try std.fmt.allocPrint(
        allocator,
        "{s}/.gud-git/trees/{s}",
        .{ cwd_path, commit_name },
    );
    defer allocator.free(base_path);

    std.fs.makeDirAbsolute(base_path) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print("commit already exists", .{});
                return err;
            }, // Do nothing, it's OK
            else => return err, // Propagate other errors
        }
    };

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const init_name = try allocator.alloc(u8, 4);
    std.mem.copyForwards(u8, init_name, "init");
    const parsed_node = try tree.Node.create(allocator, cwd_iterable, init_name, rand);
    defer parsed_node.destroy(allocator);

    const node_save_dir: std.fs.Dir = try std.fs.openDirAbsolute(base_path, .{});
    const blob_save_dir: std.fs.Dir = try cwd_iterable.openDir(".gud-git/blobs/", .{});
    try parsed_node.save(
        allocator,
        node_save_dir,
        blob_save_dir,
    );
}

pub fn status() !void {}
pub fn clone_repo() !void {
    std.debug.print("clone repo", .{});
}
pub fn init_repo(init_dir: std.fs.Dir) !void {
    std.debug.print("init repo", .{});

    init_dir.makeDir(".gud-git") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print(".gud-git dir already exists", .{});
                return;
            }, // Do nothing, it's OK
            else => return err, // Propagate other errors
        }
    };

    try init_dir.makeDir(".gud-git/trees/");
    try init_dir.makeDir(".gud-git/blobs/");
}
