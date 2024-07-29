const root = @import("root.zig");

pub fn main() !void {
    const rawInput = "https://username:password@google.com:8080/some/path/:named/?query=string#hash";
    const pattern = root.parse(rawInput);
    _ = pattern;
}
