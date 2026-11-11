username: Username,
password: Password,
token: Token,

const Account = @This();

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const bcrypt = std.crypto.pwhash.bcrypt;
const hasUniqueRepresentation = std.meta.hasUniqueRepresentation;

const Authentication = extern struct {
    password: Password,
    token: Token,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }
};

pub const Username = extern struct {
    /// All the inactive bytes are zeroes.
    bytes: Bytes,

    pub const length_max = 15;

    const Bytes = [length_max:0]u8;

    comptime {
        assert(@sizeOf(Bytes) == @sizeOf(u128));
        assert(hasUniqueRepresentation(@This()));
    }

    const empty: Username = .{ .bytes = @splat(0) };

    fn toU128(username: *const Username) u128 {
        return @bitCast(username.bytes);
    }

    pub fn fromSlice(slice: []const u8) ?Account.Username {
        if (slice.len == 0) return null;
        if (Account.Username.length_max < slice.len) return null;

        var result: Username = .empty;
        defer assert(result.bytes[length_max] == 0);

        for (slice) |char|
            if (!std.ascii.isAlphanumeric(char) and char != '_')
                return null;

        @memcpy(result.bytes[0..slice.len], slice);
        return result;
    }

    pub fn toSlice(username: *const Username) [:0]const u8 {
        assert(username.bytes[length_max] == 0);
        return mem.span(@as([*:0]const u8, &username.bytes));
    }
};

pub const Password = extern struct {
    hash: [hash_size]u8,

    const hash_size = 67;

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub fn init(csprng: std.Random, string: []const u8) Password {
        var salt: [bcrypt.salt_length]u8 = undefined;
        csprng.bytes(&salt);

        var pw: Password = undefined;
        // The error set of this function is a mess,
        // it's generalized for all kinds of hashers,
        // some of them spawn threads, etc.
        const hash_slice = bcrypt.strHashWithSalt(string, .{
            .encoding = .phc,
            .params = .owasp,
        }, &pw.hash, salt) catch unreachable;
        assert(hash_slice.len == pw.hash.len);
        return pw;
    }

    pub fn verify(pw: *const Password, string: []const u8) bool {
        if (bcrypt.strVerify(&pw.hash, string, .{
            .silently_truncate_password = false,
        })) {
            return true;
        } else |err| switch (err) {
            error.Canceled => unreachable, // No `Io` involved.
            else => return false,
        }
    }
};

pub const Token = extern struct {
    pub const length = 64;

    chars: [length]u8,

    pub fn random(csprng: std.Random) Token {
        var t: Token = undefined;
        for (&t.chars) |*char|
            char.* = csprng.intRangeAtMost(u8, 'a', 'z');

        return t;
    }

    pub fn eql(token: *const Token, string: []const u8) bool {
        return mem.eql(u8, &token.chars, string);
    }
};

pub const Index = enum(u32) {
    _,

    pub fn fromUid(uid: u32) ?Account.Index {
        if (uid == 0) return null;
        return @fromBackingInt(uid - 1);
    }

    pub fn toUid(index: Account.Index) u32 {
        return @backingInt(index) + 1;
    }
};

pub const Storage = struct {
    map: std.array_hash_map.Auto(Username, Authentication),

    pub const empty: Storage = .{ .map = .empty };

    pub fn count(storage: *const Storage) usize {
        return storage.map.count();
    }

    pub fn countFromSizeInBytes(size_in_bytes: usize) usize {
        const bytes_per_account = @sizeOf(Username) + @sizeOf(Authentication);
        return @divExact(size_in_bytes, bytes_per_account);
    }

    pub fn setLength(storage: *Storage, len: usize) void {
        assert(storage.map.capacity() >= len);
        storage.map.entries.len = len;
    }

    pub fn vector(storage: *const Storage) [2][]u8 {
        return .{
            @ptrCast(storage.map.keys()),
            @ptrCast(storage.map.values()),
        };
    }

    pub fn initCapacity(gpa: Allocator, capacity: usize) Allocator.Error!Storage {
        var storage: Storage = .empty;
        try storage.map.ensureTotalCapacity(gpa, capacity);

        return storage;
    }

    pub fn deinit(storage: *Account.Storage, gpa: Allocator) void {
        storage.map.deinit(gpa);
    }

    /// Set the storage to an empty state, making deinitialization a no-op,
    /// and returning a copy of the original.
    pub fn move(storage: *Account.Storage) Account.Storage {
        return .{ .map = storage.map.move() };
    }

    pub fn reIndex(storage: *Account.Storage, gpa: Allocator) Allocator.Error!void {
        return storage.map.reIndex(gpa);
    }

    pub fn getByIndex(storage: *const Account.Storage, index: Account.Index) ?Account {
        const index_int = @backingInt(index);
        if (storage.map.count() <= index_int) return null;

        const username = storage.map.keys()[index_int];
        const authentication = storage.map.values()[index_int];

        return .{
            .username = username,
            .password = authentication.password,
            .token = authentication.token,
        };
    }

    pub const GetOrPut = struct {
        index: Account.Index,
        found_existing: bool,
    };

    pub fn getOrPut(
        storage: *Account.Storage,
        gpa: Allocator,
        account: Account,
    ) Allocator.Error!GetOrPut {
        const gop = try storage.map.getOrPut(gpa, account.username);

        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .token = account.token,
                .password = account.password,
            };
        }

        return .{
            .index = @fromBackingInt(@intCast(gop.index)),
            .found_existing = gop.found_existing,
        };
    }
};
