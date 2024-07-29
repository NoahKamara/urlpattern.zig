const std = @import("std");
const CharacterSet = @import("CharacterSet.zig");

const source_module = @import("source.zig");
const SourceRange = source_module.SourceRange;
const SourceText = source_module.SourceText;

const Allocator = std.mem.Allocator;

const Tokenizer = struct {
    const Self = @This();

    allocator: Allocator,
    source: SourceRange,

    is_destroyed: bool = false,
    policy: TokenizePolicy,
    index: usize = 0,
    next_index: usize = 0,
    has_ended: bool = false,

    fn init(source_text: SourceText, allocator: Allocator) *Self {
        const tokenizer = allocator.create(Tokenizer) catch unreachable;

        tokenizer.* = Self{
            .allocator = allocator,
            .source = source_text.slice(),
            .policy = .strict,
            .index = 0,
            .next_index = 0,
        };

        return tokenizer;
    }

    fn processError(self: *Self, next_pos: usize, value_pos: usize) !Token {
        if (self.policy == .strict) {
            std.log.warn("Tokenizer error: {d}..{d}", .{ value_pos, next_pos });
            return error.InvalidToken;
        }

        return Token{
            .kind = TokenKind.invalid_char,
            .range = try self.source.slice(value_pos, next_pos - value_pos),
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn next(self: *Self) !?Token {
        const char = self.seek() orelse return {
            if (self.has_ended) {
                return null;
            } else {
                self.has_ended = true;
                return Token{
                    .kind = .end,
                    .range = .{
                        .index = self.source.length,
                        .length = 0,
                        .source = self.source.source,
                    },
                };
            }
        };

        const kind: TokenKind = switch (char) {
            '{' => TokenKind.open,
            '}' => TokenKind.close,
            '*' => TokenKind.asterisk,
            '?' | '+' => TokenKind.other_modifier,
            '\\' => {
                const start_index = self.index;
                _ = self.seek() orelse return error.ExpectedEscapedChar;

                return Token{
                    .kind = TokenKind.escaped_char,
                    .range = try self.source.slice(start_index, 2),
                };
            },
            ':' => {
                const start_position = self.index;
                var name_position = start_position + 1;

                while (name_position < self.source.length) {
                    defer name_position += 1;
                    const allowedChars = CharacterSet.init(.{
                        CharacterSet.range('a', 'z'),
                        CharacterSet.range('A', 'Z'),
                        CharacterSet.range('0', '9'),
                        '_',
                        '$',
                    });

                    if (self.source.contentAtOffset(name_position)) |name_char| {
                        if (allowedChars.contains(name_char)) {
                            continue;
                        } else {
                            name_position -= 1;
                        }
                    }

                    break;
                }

                var length = (name_position - start_position);

                if (length <= 1) {
                    return try self.processError(name_position, start_position);
                }

                if (self.policy == .lenient) {
                    length = 1;
                }

                self.next_index = self.index + length;

                return Token{
                    .kind = TokenKind.name,
                    .range = try self.source.slice(start_position, length),
                };
            },
            else => TokenKind.char,
        };

        const slice = try self.source.slice(self.index, 1);

        return Token{
            .kind = kind,
            .range = slice,
        };
    }

    fn consume(self: *Self) ![]Token {
        var tokens = std.ArrayList(Token).init(self.allocator);
        while (try self.next()) |token| {
            try tokens.append(token);
        }

        defer self.deinit();

        return try tokens.toOwnedSlice();
    }

    fn seek(self: *Self) ?u8 {
        if (self.next_index >= self.source.length) {
            return null;
        }

        self.index = self.next_index;
        self.next_index += 1;
        return self.source.contentAtOffset(self.index);
    }
};

const TokenizePolicy = enum { strict, lenient };

// MARK: Interface
pub const Token = struct {
    const Self = @This();
    kind: TokenKind,
    range: SourceRange,
};

pub const TokenKind = enum {
    /// { (U+007B) code point.
    open,
    /// } (U+007D) code point.
    close,
    /// "(<regular expression>)".
    /// The regular expression is required to consist of only ASCII code points.
    regexp,
    /// ":<name>".
    /// The name value is restricted to code points that are consistent with JavaScript identifiers.
    name,
    /// a valid pattern code point without any special syntactical meaning.
    char,
    /// a char escaped using a backslash like "\<char>".
    escaped_char,
    /// matching group modifier that is either the U+003F (?) or U+002B (+) code points.
    other_modifier,
    /// The token represents a U+002A (*) code point that can be
    /// either a wildcard matching group or a matching group modifier.
    asterisk,
    /// The token represents the end of the pattern string.
    end,
    /// The token represents a code point that is invalid in the pattern. This could be because of the code point value itself or due to its location within the pattern relative to other syntactic elements.
    invalid_char,
};

pub fn tokenize(source: SourceText, policy: TokenizePolicy, allocator: std.mem.Allocator) ![]const Token {
    var tokenizer = Tokenizer.init(source, allocator);
    tokenizer.policy = policy;
    const tokens = try tokenizer.consume();
    return tokens;
}

// MARK: Tests
const testing = std.testing;

fn expectTokenKind(expectation: TokenKind, tokens: []const Token) !void {
    for (0..tokens.len) |i| {
        if (tokens[i].kind != expectation) {
            std.log.warn("expected '{s}'@{d} to be '{}' actual: '{}'", .{ tokens[i].range.content(), i, expectation, tokens[i].kind });
        }

        try testing.expectEqual(tokens[i].kind, expectation);
    }
}

fn map(Value: type, Transform: type, transform_fn: fn (Value) Transform) type {
    return struct {
        const Map = @This();
        transform_fn: fn (Value) Transform,

        fn transform(value: Value) Transform {
            return transform(value);
        }

        fn map(self: Map, array: []const Value) []const Transform {
            var transformed: [array.len]Transform = undefined;

            for (0..array.len) |index| {
                transformed[index] = self.transform(array[index]);
            }
        }
    }{ .transform_fn = transform_fn };
}

test "scheme" {
    const source = SourceText.init("https://");

    var tokenizer = Tokenizer.init(source, testing.allocator);

    tokenizer.policy = .lenient;

    const tokens = try tokenizer.consume();
    defer testing.allocator.free(tokens);

    try testing.expectEqual(9, tokens.len);
    try expectTokenKind(.char, tokens[0..5]);
    try testing.expectEqual(.invalid_char, tokens[5].kind);
}

test "asterisk" {
    const source = SourceText.init("\\**");
    const tokens = try tokenize(source, .strict, testing.allocator);

    defer testing.allocator.free(tokens);

    try testing.expectEqual(3, tokens.len);

    try testing.expectEqual(tokens[0].kind, TokenKind.escaped_char);
    try testing.expectEqual(tokens[1].kind, .asterisk);
}

test "name" {
    const source = SourceText.init("\\::a0_name");

    const tokens = try tokenize(source, .strict, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expectEqual(TokenKind.escaped_char, tokens[0].kind);

    try testing.expectEqual(TokenKind.name, tokens[1].kind);
}
