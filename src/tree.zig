const std = @import("std");

pub const Blob = struct {
    name: []u8,
    hash: []u8,
    contents: []u8,
    pub fn create(allocator: std.mem.Allocator, file: std.fs.File, name: []u8) !*Blob {
        const file_size = try file.getEndPos();

        const data_buffer = try allocator.alloc(u8, file_size);
        _ = try file.readAll(data_buffer);

        const Sha256 = std.crypto.hash.Sha1;
        var sha256 = Sha256.init(.{});
        sha256.update(data_buffer);

        const result = sha256.finalResult();
        const hash = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.fmtSliceHexLower(&result)});
        const output = try allocator.create(Blob);

        output.* =
            Blob{
                .name = name,
                .hash = hash,
                .contents = data_buffer,
            };

        return output;
    }

    pub fn save(
        self: *Blob,
        allocator: std.mem.Allocator,
        save_dir: std.fs.Dir, // eg. cwd/.gud-git/blobs/
    ) !void {
        const new_file_name = try std.fmt.allocPrint(allocator, "{}.blob", .{std.fmt.fmtSliceHexLower(self.hash)});
        defer allocator.free(new_file_name);
        std.debug.print("save blob:{s}\n", .{new_file_name});

        var save_file = save_dir.createFile(new_file_name, .{}) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {
                    std.debug.print("blob already exists: {s}", .{self.hash});
                    return;
                }, // Do nothing, it's OK
                else => {
                    std.debug.print("err while creating save file with name: {s} for blob err: {}", .{ new_file_name, err });
                    return;
                },
            }
        };

        defer save_file.close();

        try save_file.writeAll(try std.fmt.allocPrint(allocator, "{s}", .{self.contents}));
    }

    pub fn destroy(self: *Blob, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.contents);

        allocator.destroy(self);
    }
};
pub const Node = struct {
    children: std.ArrayList(*Node),
    blobs: std.ArrayList(*Blob),
    name: []u8,
    uuid: []u8,

    pub fn save(
        self: *Node,
        allocator: std.mem.Allocator,
        node_save_dir: std.fs.Dir, // eg. cwd/.gud-git/trees/test-commit-name/
        blob_save_dir: std.fs.Dir, // eg. cwd/.gud-git/blobs/
    ) !void {
        //saved file structure:
        // File name: uuid
        // 1. children nodes uuids
        // 2. blob hashes
        // 3. name
        // children;children;children;...\n
        // blob;blob;blob;\n
        // name\n

        var children_uuids = std.ArrayList(u8).init(allocator);
        for (self.children.items) |child| {
            try children_uuids.appendSlice(try std.fmt.allocPrint(allocator, "{x};", .{child.uuid}));
            try child.save(allocator, node_save_dir, blob_save_dir);
        }
        defer children_uuids.deinit();

        var blob_hashes = std.ArrayList(u8).init(allocator);
        for (self.blobs.items) |blob| {
            try blob_hashes.appendSlice(try std.fmt.allocPrint(allocator, "{x};", .{blob.hash}));
            try blob.save(allocator, blob_save_dir);
        }
        defer blob_hashes.deinit();

        const save_data = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n", .{ children_uuids.items, blob_hashes.items, self.name });
        defer allocator.free(save_data);

        const new_file_name = try std.fmt.allocPrint(allocator, "{x}.node", .{self.uuid});
        defer allocator.free(new_file_name);

        std.debug.print("save node with file name:{s}\n", .{new_file_name});
        var save_file = try node_save_dir.createFile(new_file_name, .{});
        defer save_file.close();
        try save_file.writeAll(save_data);
    }

    pub fn create(allocator: std.mem.Allocator, base_dir: std.fs.Dir, name: []u8, rand: std.Random) !*Node {
        var iterator = base_dir.iterate();

        var children = std.ArrayList(*Node).init(allocator);
        var blobs = std.ArrayList(*Blob).init(allocator);

        while (try iterator.next()) |entry| {
            std.debug.print("iterated {s}\n", .{entry.name});
            if (std.mem.eql(u8, entry.name, ".gud-git"))
                continue;

            switch (entry.kind) {
                .file => {
                    // file is closed by destroy()
                    const child_file = try base_dir.openFile(entry.name, .{});

                    // name if free-d by destroy()
                    const name_clone = try allocator.alloc(u8, entry.name.len);
                    std.mem.copyForwards(u8, name_clone, entry.name);

                    const blob = try Blob.create(allocator, child_file, name_clone);
                    try blobs.append(blob);
                },
                .directory => {
                    var child_dir = try base_dir.openDir(entry.name, .{ .iterate = true });

                    defer child_dir.close();

                    // name is free-d by destroy()
                    const name_clone = try allocator.alloc(u8, entry.name.len);
                    std.mem.copyForwards(u8, name_clone, entry.name);

                    const node = try Node.create(allocator, child_dir, name_clone, rand);
                    try children.append(node);
                },
                else => {
                    std.debug.print("WARN! the following file type is not supported by Node.create {}:", .{entry.kind});
                },
            }
        }
        var uuid: [8]u8 = undefined;
        rand.bytes(&uuid);

        const output = try allocator.create(Node);
        output.* =
            Node{
                .name = name,
                .blobs = blobs,
                .children = children,
                .uuid = &uuid,
            };

        return output;
    }

    pub fn destroy(self: *Node, allocator: std.mem.Allocator) void {
        for (self.blobs.items) |blob| {
            blob.destroy(allocator);
        }
        for (self.children.items) |child| {
            child.destroy(allocator);
        }
        // allocator.free(self.uuid);

        allocator.free(self.name);
        allocator.destroy(self);
    }
};
