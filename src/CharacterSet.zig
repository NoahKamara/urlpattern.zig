const std = @import("std");

const Self = @This();

elements: [256]bool,

fn insert(self: *Self, comptime value: u8) void {
    self.elements[value] = true;
}

fn merge(self: *Self, comptime other: Self) void {
    for (0..self.elements.len) |i| {
        if (other.elements[i]) {
            self.elements[i] = true;
        }
    }
}

pub fn get(self: *const Self, index: u8) bool {
    return self.elements[index];
}

// Set a value at a specific index
pub fn set(self: *Self, index: u8, value: bool) void {
    self.elements[index] = value;
}

pub fn init(comptime elements: anytype) Self {
    var char_set = Self{ .elements = undefined };

    inline for (elements) |item| {
        const T = @TypeOf(item);

        switch (T) {
            comptime_int, u8 => char_set.insert(item),
            []comptime_int, []u8, [*]u8 => {
                for (item) |char| {
                    char_set.insert(char);
                }
            },
            Self => char_set.merge(item),
            else => {
                std.log.warn("Unexpected type: {}\n", .{T});
                unreachable;
            },
        }
    }

    return char_set;
}

pub fn range(comptime lower: u8, comptime upper: u8) Self {
    var char_set = Self{ .elements = undefined };

    for (lower..upper + 1) |c| {
        char_set.elements[c] = true;
    }

    return char_set;
}

pub fn contains(self: Self, value: u8) bool {
    // var i: u8 = 0;

    // for (self.elements) |is_contained| {
    //     defer i += 1;
    //     if (is_contained) {
    //         std.log.warn("{c}", .{i});
    //     }
    // }

    return self.elements[value];
}

const testing = std.testing;

test "characters" {
    const allowed_chars = [_]u8{ 'b', 'c' };
    const disallowed_chars = [_]u8{ 'a', 'd' };

    const char_set = Self.init(allowed_chars);

    for (allowed_chars) |char| {
        try testing.expect(char_set.contains(char));
    }

    for (disallowed_chars) |char| {
        try testing.expect(!char_set.contains(char));
    }
}

test "range" {
    const char_set = Self.range('b', 'd');

    try testing.expect(char_set.contains('b'));
    try testing.expect(char_set.contains('c'));
    try testing.expect(char_set.contains('d'));

    try testing.expect(!char_set.contains('a'));
    try testing.expect(!char_set.contains('e'));
}

// test "invert" {
//     const allowed_chars = [_]u8{ 'a', 'd' };
//     const disallowed_chars = [_]u8{ 'b', 'c' };

//     const char_set = Self.init(allowed_chars);
//     _ = char_set.invert();

//     for (allowed_chars) |char| {
//         try testing.expect(char_set.contains(char));
//     }

//     for (disallowed_chars) |char| {
//         try testing.expect(!char_set.contains(char));
//     }
// }

test "set" {
    const allowed_chars = [_]u8{ '1', '2' };
    const disallowed_chars = [_]u8{ '0', '3' };

    const char_set = Self.init(.{ Self.range('b', 'd'), '1', '2' });

    // Check range
    try testing.expect(char_set.contains('b'));
    try testing.expect(char_set.contains('c'));
    try testing.expect(char_set.contains('d'));

    try testing.expect(!char_set.contains('a'));
    try testing.expect(!char_set.contains('e'));

    // Check standalone
    for (allowed_chars) |char| {
        try testing.expect(char_set.contains(char));
    }

    for (disallowed_chars) |char| {
        try testing.expect(!char_set.contains(char));
    }
}
