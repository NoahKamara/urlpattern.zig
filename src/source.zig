const std = @import("std");
const Allocator = @import("std").mem.Allocator;

pub const SourceRange = struct {
    source: SourceText,
    index: usize,
    length: usize,

    pub fn init(source: SourceText, index: usize, length: usize) SourceRange {
        return SourceRange{
            .source = source,
            .index = index,
            .length = length,
        };
    }

    pub fn contains(self: SourceRange, other: SourceRange) bool {
        other.index >= self.index and other.index - self.index <= self.length;
    }

    pub fn slice(self: SourceRange, offset: usize, length: usize) !SourceRange {
        const new_index = self.index + offset;
        if (new_index >= self.index + self.length) {
            return error.OutOfBounds;
        }

        return SourceRange{
            .source = self.source,
            .index = self.index + offset,
            .length = length,
        };
    }

    pub fn endIndex(self: SourceRange) usize {
        return self.index + self.length;
    }

    pub fn content(self: SourceRange) []const u8 {
        if (self.length == 0) {
            return "";
        }

        return self.source.content[self.index .. self.index + self.length];
    }

    pub fn contentAtOffset(self: SourceRange, offset: usize) ?u8 {
        if (offset >= self.length) {
            return null;
        }

        return self.content()[offset];
    }
};

pub const SourceText = struct {
    content: []const u8,

    pub fn init(content: []const u8) SourceText {
        return SourceText{ .content = content };
    }

    pub fn slice(self: SourceText) SourceRange {
        return SourceRange.init(self, 0, self.content.len);
    }
};
