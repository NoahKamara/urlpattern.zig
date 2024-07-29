const testing = @import("std").testing;

test {
    testing.refAllDecls(@This());
    testing.refAllDecls(@import("src/CharacterSet.zig"));
    testing.refAllDecls(@import("src/tokenizer.zig"));
    testing.refAllDecls(@import("src/urlparser.zig"));
    testing.refAllDecls(@import("src/patternparser.zig"));
}
