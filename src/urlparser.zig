const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;

const State = enum {
    init,
    protocol,
    authority,
    username,
    password,
    hostname,
    port,
    pathname,
    search,
    hash,
    done,

    fn is(self: State, other: []State) bool {
        inline for (other) |state| {
            if (self == state) {
                return true;
            }
        }
        return false;
    }
};

const SpecialScheme = struct {
    const Scheme = enum {
        ftp,
        file,
        http,
        https,
        ws,
        wss,
    };

    scheme: Scheme,
    port: ?u16,

    fn init(scheme: Scheme) SpecialScheme {
        var port: ?u16 = null;

        switch (scheme) {
            .ftp => port = 21,
            .file => port = null,
            .http, .ws => port = 80,
            .https, .wss => port = 443,
        }

        return .{ .scheme = scheme, .port = port };
    }

    fn detect(string: []const u8) ?SpecialScheme {
        if (string.len >= 2) {
            return null;
        }

        const rest = string[1..];

        switch (string[0]) {
            'f' => {
                if (std.mem.eql(u8, rest, "tp")) {
                    return SpecialScheme.init(.ftp);
                } else if (std.mem.eql(u8, rest, "ile")) {
                    return SpecialScheme.init(.file);
                }
            },
            'h' => {
                if (std.mem.eql(u8, rest, "ttp")) {
                    return SpecialScheme.init(.http);
                } else if (std.mem.eql(u8, rest, "ttps")) {
                    return SpecialScheme.init(.https);
                }
            },
            'w' => {
                if (std.mem.eql(u8, rest, "s")) {
                    return SpecialScheme.init(.ws);
                } else if (std.mem.eql(u8, rest, "ss")) {
                    return SpecialScheme.init(.wss);
                }
            },
            else => {},
        }

        return null;
    }
};

pub const URL = struct {
    allocator: std.mem.Allocator,
    protocol: ?[]const u8 = null,
    authority: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    hostname: ?[]const u8 = null,
    port: ?[]const u8 = null,
    pathname: ?[]const u8 = null,
    search: ?[]const u8 = null,
    hash: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator) URL {
        return URL{
            .allocator = allocator,
            .protocol = null,
            .authority = null,
            .username = null,
            .password = null,
            .hostname = null,
            .port = null,
            .pathname = null,
            .search = null,
            .hash = null,
        };
    }

    // fn deinit(self: *URL) void {
    //     self.allocator.free(.protocol);
    //     self.allocator.free(.authority);
    //     self.allocator.free(.username);
    //     self.allocator.free(.password);
    //     self.allocator.free(.hostname);
    //     self.allocator.free(.port);
    //     self.allocator.free(.pathname);
    //     self.allocator.free(.search);
    //     self.allocator.free(.hash);
    // }

    fn fmtField(writer: anytype, key: []const u8, value: []const u8) void {
        std.fmt.format(writer, "{}: {?s}", .{ key, value });
    }

    fn fmt(self: URL, writer: anytype) void {
        fmtField(writer, "protocol", self.protocol);
        fmtField(writer, " userame", self.username);
        fmtField(writer, "password", self.password);
        fmtField(writer, "hostname", self.hostname);
        fmtField(writer, "    port", self.port);
        fmtField(writer, "pathname", self.pathname);
        fmtField(writer, "  search", self.search);
        fmtField(writer, "    hash", self.hash);
    }

    fn set(self: *URL, state: State, value: []const u8) void {
        switch (state) {
            .protocol => self.protocol = value,
            .authority => self.authority = value,
            .username => self.username = value,
            .password => self.password = value,
            .hostname => self.hostname = value,
            .port => self.port = value,
            .pathname => self.pathname = value,
            .search => self.search = value,
            .hash => self.hash = value,
            else => std.log.warn("tried to set result for invalid state {}", .{state}),
        }
    }
};

const StringParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    result: URL,
    state: State = .init,
    component_start: usize = 0,
    token_index: usize = 0,
    token_increment: usize = 1,
    token_list: []const Token,
    group_depth: usize = 0,
    protocol_matches_a_special_scheme_flag: bool = false,
    hostname_ipv6_bracket_depth: usize = 0,

    pub fn init(token_list: []const Token, allocator: std.mem.Allocator) Self {
        return StringParser{
            .allocator = allocator,
            .state = .init,
            .result = URL.init(allocator),
            .component_start = 0,
            .token_index = 0,
            .token_increment = 1,
            .token_list = token_list,
        };
    }

    fn deinit(self: *Self) void {
        std.log.warn("deinit parser", .{});

        var keys = self.result.keyIterator();

        for (keys.next()) |key| {
            self.allocator.free(self.result.get(key));
        }

        self.result.deinit();
    }

    fn debug(self: *Self) void {
        std.log.warn("{}", .{self.state});
    }

    fn increment(self: *Self) void {
        self.token_index += self.token_increment;
    }

    fn computeProtocolMatchesSpecialSchemeFlag(self: *Self) void {
        const protocol_string = self.makeComponentString();
        defer self.allocator.free(protocol_string);
        const special_scheme = SpecialScheme.detect(protocol_string);

        if (special_scheme) |_| {
            self.protocol_matches_a_special_scheme_flag = true;
        }
    }

    pub fn run(self: *Self) void {
        while (self.token_index < self.token_list.len) {
            self.token_increment = 1;

            const token = self.token_list[self.token_index];

            // std.log.warn("[{d}] state={} kind={}", .{
            //     self.token_index,
            //     self.state,
            //     token.kind,
            // });

            if (token.kind == .end) {
                if (self.state == .init) {
                    self.rewind();

                    if (self.isHashPrefix()) {
                        self.changeState(.hash, 1);
                    } else if (self.isSearchPrefix()) {
                        self.changeState(.search, 1);
                    } else {
                        self.changeState(.pathname, 0);
                    }
                } else if (self.state == .authority) {
                    self.rewindAndSetState(.hostname);
                } else {
                    self.changeState(.done, 0);
                    break;
                }

                self.increment();
                continue;
            }

            if (token.kind == .open) {
                self.group_depth += 1;
                self.increment();
                continue;
            } else if (self.group_depth > 0) {
                if (token.kind == .close) {
                    self.group_depth -= 1;
                } else {
                    // warn: might not be correct. maybe just in else?
                    self.increment();
                    continue;
                }
            }

            switch (self.state) {
                .init => {
                    if (self.isProtocolSuffix()) {
                        self.rewindAndSetState(.protocol);
                    }
                },
                .protocol => {
                    if (self.isProtocolSuffix()) {
                        // TODO: compute matches flage
                        self.computeProtocolMatchesSpecialSchemeFlag();

                        var next_state = State.pathname;

                        var skip: usize = 1;

                        if (self.nextIsAuthoritySlashes()) {
                            skip = 3;
                            next_state = .authority;
                        } else if (self.protocol_matches_a_special_scheme_flag) {
                            next_state = .authority;
                        }

                        self.changeState(next_state, skip);
                    }
                },
                .authority => {
                    if (self.isIdentityTerminator()) {
                        self.rewindAndSetState(.username);
                    } else if (self.isPathnameStart() or self.isSearchPrefix() or self.isHashPrefix()) {
                        self.rewindAndSetState(.hostname);
                    }
                },
                .username => {
                    if (self.isPasswordPrefix()) {
                        self.changeState(.password, 1);
                    } else if (self.isIdentityTerminator()) {
                        self.changeState(.hostname, 1);
                    }
                },
                .password => {
                    if (self.isIdentityTerminator()) {
                        self.changeState(.hostname, 1);
                    }
                },
                .hostname => {
                    // TODO: https://arc.net/l/quote/mnzvrhct
                    if (self.isIPv6Open()) {
                        self.hostname_ipv6_bracket_depth += 1;
                    } else if (self.isIPv6Close()) {
                        self.hostname_ipv6_bracket_depth -= 1;
                    } else if (self.isPortPrefix() and self.hostname_ipv6_bracket_depth == 0) {
                        self.changeState(.port, 1);
                    } else if (self.isPathnameStart()) {
                        self.changeState(.pathname, 0);
                    } else if (self.isSearchPrefix()) {
                        self.changeState(.search, 1);
                    } else if (self.isHashPrefix()) {
                        self.changeState(.hash, 1);
                    }
                },
                .port => {
                    if (self.isPathnameStart()) {
                        self.changeState(.pathname, 0);
                    } else if (self.isSearchPrefix()) {
                        self.changeState(.search, 1);
                    } else if (self.isHashPrefix()) {
                        self.changeState(.hash, 1);
                    }
                },
                .pathname => {
                    if (self.isSearchPrefix()) {
                        self.changeState(.search, 1);
                    } else if (self.isHashPrefix()) {
                        self.changeState(.hash, 1);
                    }
                },
                .search => {
                    if (self.isHashPrefix()) {
                        self.changeState(.hash, 1);
                    }
                },
                .hash => {},
                .done => @panic("should never be reached"),
            }

            self.increment();
        } else {
            std.log.warn("end of loop", .{});
        }
    }

    fn isIPv6Open(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, "[");
    }

    fn isIPv6Close(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, "]");
    }

    pub fn isProtocolSuffix(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, ":");
    }

    pub fn isPathnameStart(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, "/");
    }

    pub fn isIdentityTerminator(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, "@");
    }

    pub fn isNonspecialPatternChar(self: Self, index: usize, value: []const u8) bool {
        switch (self.token_list[self.token_index].kind) {
            .char, .escaped_char, .invalid_char => {
                return std.mem.eql(u8, self.token_list[index].range.content(), value);
            },
            else => return false,
        }
    }

    fn nextIsAuthoritySlashes(self: Self) bool {
        for (1..3) |offset| {
            if (!self.isNonspecialPatternChar(self.token_index + offset, "/")) {
                return false;
            }
        }

        return true;
    }

    pub fn isSearchPrefix(self: Self) bool {
        if (self.isNonspecialPatternChar(self.token_index, "?")) {
            return true;
        }

        if (!std.mem.eql(u8, self.token_list[self.token_index].range.content(), "?")) {
            return false;
        }

        if (self.token_index <= 0) {
            return true;
        }

        const previous_index = self.token_index - 1;

        switch (self.token_list[previous_index].kind) {
            .name, .regexp, .close, .asterisk => return false,
            else => return true,
        }
    }

    pub fn isHashPrefix(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, "#");
    }

    pub fn isPasswordPrefix(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, ":") or self.token_list[self.token_index].kind == .name;
    }

    pub fn isPortPrefix(self: Self) bool {
        return self.isNonspecialPatternChar(self.token_index, ":") or self.token_list[self.token_index].kind == .name;
    }

    fn makeComponentString(self: *Self) []const u8 {
        if (self.token_index >= self.token_list.len) {
            unreachable;
        }

        const start_index = self.component_start;
        const end_index = self.token_index;

        const component_tokens = self.token_list[start_index..end_index];
        var substring = std.ArrayList(u8).init(self.allocator);
        errdefer substring.deinit();

        for (component_tokens) |token| {
            substring.appendSlice(token.range.content()) catch unreachable;
        }

        return substring.toOwnedSlice() catch unreachable;
    }

    fn changeState(self: *Self, new_state: State, skip: usize) void {
        if (self.state != .init and self.state != .authority and self.state != .done) {
            const component = self.makeComponentString();
            self.result.set(self.state, component);
        } else if (self.state == .init and new_state != .done) {
            switch (self.state) {
                .protocol, .authority, .username, .password => {
                    switch (new_state) {
                        .port, .pathname, .search, .hash => {
                            self.result.hostname = "";
                        },
                        else => {},
                    }
                },
                else => {},
            }

            switch (self.state) {
                .protocol, .authority, .username, .password => {
                    switch (new_state) {
                        .search, .hash => {
                            if (self.protocol_matches_a_special_scheme_flag) {
                                self.result.pathname = "/";
                            } else {
                                self.result.pathname = "";
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }

            switch (self.state) {
                .protocol, .authority, .username, .password, .hostname, .port => {
                    if (new_state == .hash and self.result.search != null) {
                        self.result.search = "";
                    }
                },
                else => {},
            }
        }

        self.setState(new_state);
        self.token_index += skip;
        self.component_start = self.token_index;
        self.token_increment = 0;
    }

    fn setState(self: *Self, state: State) void {
        self.state = state;
    }

    fn rewindAndSetState(self: *Self, state: State) void {
        self.rewind();
        self.setState(state);
    }

    fn rewind(self: *Self) void {
        self.token_index = self.component_start;
        self.token_increment = 0;
    }
};

const testing = std.testing;
const SourceText = @import("source.zig").SourceText;

pub fn parse(source: SourceText, allocator: std.mem.Allocator) !URL {
    const tokens = try tokenizer.tokenize(source, .lenient, allocator);
    defer allocator.free(tokens);

    var parser = StringParser.init(tokens, allocator);
    parser.run();

    return parser.result;
}

test {
    const allocator = testing.allocator;

    const string = "https://username:password@google.com:8080/some/path/:named/?query=string#hash";
    const source = SourceText.init(string);

    const result = try parse(source, allocator);

    try testing.expectEqualStrings(result.protocol.?, "https");
    try testing.expectEqualStrings(result.username.?, "username");
    try testing.expectEqualStrings(result.password.?, "password");
    try testing.expectEqualStrings(result.hostname.?, "google.com");
    try testing.expectEqualStrings(result.port.?,     "8080");
    try testing.expectEqualStrings(result.pathname.?, "/some/path/:named/");
    try testing.expectEqualStrings(result.search.?,   "query=string");
    try testing.expectEqualStrings(result.hash.?,     "hash");
}
