const std = @import("std");

const rdb = @cImport(@cInclude("rocksdb/c.h"));
const clib = @cImport(@cInclude("stdlib.h"));

pub const Buffer = struct {
    buff: [*]u8,
    length: usize,

    pub fn deinit(self: *const Buffer) void {
        clib.free(@ptrCast(self.buff));
    }

    pub fn into(self: *Buffer, T: type) *T {
        return @ptrCast(self.buff);
    }
};

pub const Error = struct {
    message: [*:0]u8,

    pub fn deinit(self: *const Error) void {
        clib.free(self.message);
    }
};

pub const NotFound = struct {
    pub fn deinit(_: *const NotFound) void {
        // nothing here.
    }
};

pub const Result = union(enum) {
    result: Buffer,
    err: Error,
    not_found: NotFound,
    pub fn deinit(self: *const Result) void {
        switch (self.*) {
            inline else => |o| o.deinit(),
        }
    }
};

pub const ReadOptions = struct {
    readOptions: *rdb.rocksdb_readoptions_t,

    pub fn init() ReadOptions {
        return .{ .readOptions = rdb.rocksdb_readoptions_create().? };
    }

    pub fn deinit(self: *const ReadOptions) void {
        clib.free(self.readOptions);
    }
};

pub const WriteOptions = struct {
    writeOptions: *rdb.rocksdb_writeoptions_t,

    pub fn init() WriteOptions {
        return .{ .writeOptions = rdb.rocksdb_writeoptions_create().? };
    }

    pub fn deinit(self: *const WriteOptions) void {
        clib.free(self.writeOptions);
    }
};

pub const RocksDB = struct {
    db: *rdb.rocksdb_t,

    pub fn open(dir: []const u8) union(enum) { rocksdb: RocksDB, err: Error } {
        const options = rdb.rocksdb_options_create().?;
        rdb.rocksdb_options_set_create_if_missing(options, 1);
        const err: [*c]u8 = null;

        const db = rdb.rocksdb_open(options, @ptrCast(dir), @constCast(@ptrCast(&err)));
        if (err) |message| {
            return .{ .err = .{ .message = message } };
        }

        return .{ .rocksdb = RocksDB{ .db = db.? } };
    }

    pub fn get(self: RocksDB, options: ReadOptions, key: []const u8) Result {
        var valueLength: usize = 0;
        var err: [*c]u8 = null;
        const v = rdb.rocksdb_get(
            self.db,
            options.readOptions,
            @ptrCast(key),
            key.len,
            &valueLength,
            &err,
        );
        if (err) |message| {
            return .{ .err = .{ .message = message } };
        }
        if (v == 0) {
            return .{ .not_found = .{} };
        }

        return .{ .result = .{ .buff = @ptrCast(v), .length = valueLength } };
    }

    pub fn set(self: RocksDB, options: WriteOptions, key: []const u8, value: []const u8) ?Error {
        var err: [*c]u8 = null;
        rdb.rocksdb_put(
            self.db,
            options.writeOptions,
            @ptrCast(key),
            key.len,
            @ptrCast(value.ptr),
            value.len,
            &err,
        );
        if (err) |message| {
            return .{ .message = message };
        }

        return null;
    }

    pub fn close(self: RocksDB) void {
        rdb.rocksdb_close(self.db);
    }
};

test "open write read close" {
    const rocksDB = RocksDB.open("./test.db");

    switch (rocksDB) {
        .rocksdb => |rocks| {
            std.log.info("Opened rocksdb", .{});
            defer rocks.close();

            const writeOptions = WriteOptions.init();
            defer writeOptions.deinit();

            _ = rocks.set(writeOptions, "hello", "world");

            const readOptions = ReadOptions.init();
            defer readOptions.deinit();

            const result = rocks.get(readOptions, "hello");
            defer result.deinit();

            switch (result) {
                .result => |value| std.log.info("Found result: {d} bytes", .{value.length}),
                .err => |err| std.log.err("Error reading: {*}", .{err.message}),
                .not_found => std.log.err("Not found key", .{}),
            }
        },
        .err => |err| {
            defer err.deinit();
            std.log.err("Error opening rocksdb {*}", .{err.message});
        },
    }
}
