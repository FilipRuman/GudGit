const std = @import("std");

pub fn main() !void {
    try parse_passed_arguments_form_command_line();
}

pub fn parse_passed_arguments_form_command_line() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args, 0..) |arg, i| {
        std.debug.print("Arg {}:{s}\n", .{ i, arg });
    }
    if (args.len > 1) {
        const operation_name = args[1];

        if (std.mem.eql(u8, operation_name, "init")) {
            try init_repo(std.fs.cwd());
        } else if (std.mem.eql(u8, operation_name, "clone")) {
            try clone_repo();
        }
    }
}
pub fn clone_repo() !void {
    std.debug.print("clone repo", .{});
}
const basePath: []const u8 = ".gud-git/";
pub fn init_repo(init_dir: std.fs.Dir) !void {
    std.debug.print("init repo", .{});

    init_dir.makeDir(".gud-git") catch |err| {
        switch (err) {
            error.PathAlreadyExists => {
                std.debug.print(".gud-git dir already exists", .{});
            }, // Do nothing, it's OK
            else => return err, // Propagate other errors
        }
    };

    var base_dir = try init_dir.openDir(basePath, .{});
    const file = try base_dir.createFile("test.md", .{});
    defer file.close();
    try file.writer().writeAll("HELLO FROM zig und zag!");
}
