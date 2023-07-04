const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const stderr = std.io.getStdErr().writer(); // TODO: Remove

pub const TokenIterator = struct {
    buf: []const u8,
    index: usize,

    const Self = @This();

    pub fn next(self: *Self) ?Token {
        // If the index is out-of-bounds then we are done now and forever
        if (self.index >= self.buf.len) return null;

        // First, skip any whitespace. Return null if nothing else remains
        const start = std.mem.indexOfNonePos(u8, self.buf, self.index, " ,\t\r\n") orelse {
            self.index = self.buf.len;
            return null;
        };

        switch (self.buf[start]) {
            '"' => { // Parse a string
                var strStart = start + 1;
                var end = start + 1;
                var keepLookin = true;
                while (keepLookin) {
                    // Out-of-bounds: unterminated string. Return string as slice from start to end of buffer.
                    if (end >= self.buf.len) {
                        self.index = self.buf.len;
                        return .{ .string = self.buf[start..(self.buf.len)] };
                    }

                    end = std.mem.indexOfPos(u8, self.buf, end, "\"") orelse self.buf.len;

                    if (self.buf[end - 1] != '\\') {
                        // We found the end!
                        keepLookin = false;
                    } else {
                        // Found a quote, but it was escaped. Search from next character
                        end += 1;
                    }
                }
                self.index = end + 1;
                return .{ .string = self.buf[strStart..end] };
            },
            '#' => { // Ignore a comment (by recursively returning the next non-comment token)
                self.index = std.mem.indexOfAnyPos(u8, self.buf, start, "\r\n") orelse self.buf.len;
                return self.next();
            },
            '[' => {
                self.index = start + 1;
                return .left_bracket;
            },
            ']' => {
                self.index = start + 1;
                return .right_bracket;
            },
            else => { // Parse a token
                var end = std.mem.indexOfAnyPos(u8, self.buf, start, "[] ,\t\r\n") orelse self.buf.len;
                self.index = end;
                return Token.parseOneToken(self.buf[start..end]);
            },
        }
    }
};

pub const Token = union(enum) {
    left_bracket: void,
    right_bracket: void,
    bool: bool,
    i64: i64,
    f64: f64,
    term: []const u8,
    deferred_term: []const u8,
    string: []const u8,
    none: void,

    pub fn parse(code: []const u8) TokenIterator {
        return .{
            .buf = code,
            .index = 0,
        };
    }

    fn parseOneToken(part: []const u8) Token {
        if (std.mem.eql(u8, part, "[")) {
            return .left_bracket;
        }
        if (std.mem.eql(u8, part, "]")) {
            return .right_bracket;
        }
        if (std.mem.eql(u8, part, "true")) {
            return .{ .bool = true };
        }
        if (std.mem.eql(u8, part, "false")) {
            return .{ .bool = false };
        }
        if (std.mem.startsWith(u8, part, "\\")) {
            const deferredTerm = part[1..];
            return .{ .deferred_term = deferredTerm };
        }
        if (std.fmt.parseInt(i64, part, 10)) |i| {
            return .{ .i64 = i };
        } else |_| {}
        if (std.fmt.parseFloat(f64, part)) |f| {
            return .{ .f64 = f };
        } else |_| {}

        return .{ .term = part };
    }

    // fn parseString(alloc: Allocator, contents: []const u8) Token {
    //     var hasNewlines = std.mem.containsAtLeast(u8, contents, 1, "\\n");
    //     var hasQuotes = std.mem.containsAtLeast(u8, contents, 1, "\\");

    //     // Contains no escapes, just exit
    //     if (!hasNewlines and !hasQuotes) return .{ .string = contents };

    //     // Contains escapes, handle them

    //     // Newlines
    //     var rsize = std.mem.replacementSize(u8, contents, "\\n", "\n");
    //     var unescapedNewlines = try alloc.alloc(u8, rsize);
    //     _ = std.mem.replace(u8, contents, "\\n", "\n", unescapedNewlines);

    //     // Quotes
    //     rsize = std.mem.replacementSize(u8, contents, "\\\"", "\"");
    //     var unescaped = try alloc.alloc(u8, rsize);
    //     _ = std.mem.replace(u8, contents, "\\\"", "\"", unescaped);

    //     return .{ .string = unescaped };
    // }

    fn assertEql(self: Token, other: Token) void {
        switch (self) {
            .left_bracket => std.debug.assert(other == Token.left_bracket),
            .right_bracket => std.debug.assert(other == Token.right_bracket),
            .bool => |b| std.debug.assert(other.bool == b),
            .i64 => |i| std.debug.assert(other.i64 == i),
            .f64 => |f| std.debug.assert(other.f64 == f),
            .string => |s| std.debug.assert(std.mem.eql(u8, other.string, s)),
            .term => |t| std.debug.assert(std.mem.eql(u8, other.term, t)),
            .deferred_term => |t| std.debug.assert(std.mem.eql(u8, other.deferred_term, t)),
            .none => std.debug.assert(other == Token.none),
        }
    }
};

// Testing!

test "parse hello.rock" {
    var expected = ArrayList(Token).init(std.testing.allocator);
    defer expected.deinit();
    try expected.append(Token.left_bracket);
    try expected.append(Token{ .string = "hello" });
    try expected.append(Token{ .term = "pl" });
    try expected.append(Token.right_bracket);
    try expected.append(Token{ .deferred_term = "greet" });
    try expected.append(Token{ .term = "def" });

    const helloFile = @embedFile("test/hello.rock");
    const tokens = try Token.parse(std.testing.allocator, helloFile);
    defer tokens.deinit();

    std.debug.assert(tokens.items.len == 6);
    var i: u8 = 0;
    while (i < 6) {
        std.debug.print("Expected: {any}, Actual: {any} ... ", .{ expected.items[i], tokens.items[i] });
        expected.items[i].assertEql(tokens.items[i]);
        std.debug.print("PASS\n", .{});
        i += 1;
    }
}
