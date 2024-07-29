const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const SourceText = @import("source.zig").SourceText;
const URL = @import("urlparser.zig").URL;
const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;

const URLPatternPart = struct {};

const PatternParser = struct {
    tokens: []const Token,
    index: usize = 0,
    parts: std.ArrayList(URLPatternPart),

    fn init(tokens: []const Token) PatternParser {
        return PatternParser{
            .tokens = tokens,
        };
    }

    fn parse(self: *PatternParser) !URLPattern.Component {
        while (self.index < self.tokens.len) {
            defer self.index += 1;
            const char = self.consumeToken(.char);
            const name = self.consumeToken(.name);
            const regexp_or_wildcard = self.consumeRegexpOrWildcard(name);

            if (name != null or regexp_or_wildcard != null) {
                var prefix = "";

                if (char) |token| {
                    prefix = token.range.content();
                }

                self.maybeAddPartFromPendigPrefix();

                const modifier = self.consumeModifierToken();
                self.addPart(prefix, name, regexp_or_wildcard, "", modifier);
                continue;
            }

            var fixed = char;

            if (fixed == null) {
                fixed = self.consumeToken(.escaped_char);
            }

            if (fixed != null) {
                self.pending_fixed.appendSlice(fixed);
                // TODO: Check in DOCU
                self.consumeToken(kind: TokenKind)
            }

            if (self.consumeToken(.open)) |open| {
                const prefix = self.consumeText();
                name = self.consumeToken(.name);
                regexp_or_wildcard = self.consumeRegexpOrWildcard(name);

                const suffix = self.consumeText();
                self.consumeRequiredToken(.close);
                modifier = self.consumeModifierToken();
                self.addPart(prefix, name, regexp_or_wildcard, suffix, modifier);
                continue;
            }

            self.maybeAddpartFromPendingFixed();
            consumeRequiredToken(.end);
        }

        return self.parts.toOwnedSlice();
    }

    fn consumeRegexpOrWildcard(self: *PatternParser, name_token: ?Token) ?Token {
        var token = self.consumeToken(.regexp);

        if (name_token == null and token == null) {
            token = self.consumeToken(.asterisk);
        }

        return token;
    }

    fn consumeToken(self: *PatternParser, kind: TokenKind) ?Token {
        if (self.index > self.tokens.len) {
            unreachable;
        }

        const next_token = self.tokens[self.index];
        if (next_token.kind == kind) {
            return null;
        }

        self.index += 1;

        return next_token;
    }
};

pub fn parseComponent(
    value: ?[]const u8,
    allocator: std.mem.Allocator,
) !?URLPattern.Component {
    if (value) |string| {
        const source = SourceText.init(string);

        const tokens = try tokenizer.tokenize(source, .strict, allocator);
        defer allocator.free(tokens);

        var parser = PatternParser.init(tokens);
        return try parser.parse();
    } else {
        return null;
    }
}

pub const URLPattern = struct {
    pub const Component = struct {
        pattern: []const u8,
        regexp: []const u8,
        groups: []const []const u8,
        has_regexp_groups: bool,
    };

    protocol: ?Component,
    username: ?Component,
    password: ?Component,
    hostname: ?Component,
    port: ?Component,
    pathname: ?Component,
    search: ?Component,
    hash: ?Component,
};

pub fn parse(url: URL, allocator: std.mem.Allocator) !URLPattern {
    return URLPattern{
        .protocol = try parseComponent(url.protocol, allocator),
        .username = try parseComponent(url.username, allocator),
        .password = try parseComponent(url.password, allocator),
        .hostname = try parseComponent(url.hostname, allocator),
        .port = try parseComponent(url.port, allocator),
        .pathname = try parseComponent(url.pathname, allocator),
        .search = try parseComponent(url.search, allocator),
        .hash = try parseComponent(url.hash, allocator),
    };
}

const testing = std.testing;

test "special scheme" {
    const patterns = [_][]const u8{ "ftp", "file", "http", "https", "ws", "wss" };

    for (patterns) |pattern| {
        const component = try parseComponent(pattern, testing.allocator);

        try testing.expect(component != null);
        try testing.expectEqualStrings("", component.?.pattern);
    }
}

// test "catchall" {
//     const component = try parseComponent("*", testing.allocator);
//     try testing.expect(component != null);
//     try testing.expectEqualStrings("", component.?.pattern);
// }
