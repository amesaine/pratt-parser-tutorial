pub const Token = union(enum) {
    atom: char,
    op: char,
    eof,
};

input: string,
i: usize,

pub fn next(l: *Lexer) Token {
    var result: Token = .eof;

    while (l.i < l.input.len) {
        const ch = l.input[l.i];
        switch (ch) {
            ' ',
            '\n',
            '\t',
            '\r',
            => l.i += 1,

            '0'...'9',
            'a'...'z',
            => {
                result = .{ .atom = ch };
                break;
            },

            '+', '-', '*', '/', '=', '!', '[', ']', '(', ')', '?', ':' => {
                result = .{ .op = ch };
                break;
            },

            else => std.debug.panic("Unsupported token: {c}", .{ch}),
        }
    }

    l.i += 1;
    return result;
}

const std = @import("std");
const char = u8;
const string = []const char;
const Lexer = @This();
