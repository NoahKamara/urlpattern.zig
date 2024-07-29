const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("Tokenizer.zig");
const SourceText = @import("source.zig").SourceText;
const urlparser = @import("urlparser.zig");
const patternparser = @import("patternparser.zig");

pub const URLPattern = patternparser.URLPattern;

pub fn parseAlloc(input: []const u8, allocator: Allocator) !URLPattern {
    const source = SourceText.init(input);
    const url = try urlparser.parse(source, allocator);

    std.log.debug("{s}: {?s}\n", .{ "protocol", url.protocol });
    std.log.debug("{s}: {?s}\n", .{ " userame", url.username });
    std.log.debug("{s}: {?s}\n", .{ "password", url.password });
    std.log.debug("{s}: {?s}\n", .{ "hostname", url.hostname });
    std.log.debug("{s}: {?s}\n", .{ "    port", url.port });
    std.log.debug("{s}: {?s}\n", .{ "pathname", url.pathname });
    std.log.debug("{s}: {?s}\n", .{ "  search", url.search });
    std.log.debug("{s}: {?s}\n", .{ "    hash", url.hash });

    const pattern = try patternparser.parse(url, allocator);

    std.log.debugt("{s}: {?s}\n", .{ "protocol", pattern.protocol });
    std.log.debug("{s}: {?s}\n", .{ " userame", pattern.username });
    std.log.debug("{s}: {?s}\n", .{ "password", pattern.password });
    std.log.debug("{s}: {?s}\n", .{ "hostname", pattern.hostname });
    std.log.debug("{s}: {?s}\n", .{ "    port", pattern.port });
    std.log.debug("{s}: {?s}\n", .{ "pathname", pattern.pathname });
    std.log.debug("{s}: {?s}\n", .{ "  search", pattern.search });
    std.log.debug("{s}: {?s}\n", .{ "    hash", pattern.hash });

    return pattern;
}

pub fn parse(input: []const u8) !URLPattern {
    return try parseAlloc(input, std.heap.c_allocator);
}
