left: u8,
right: u8,

pub fn prefix(op: char) BindingPower {
    return switch (op) {
        '-' => .{ .left = 0, .right = 9 },
        else => std.debug.panic("Invalid prefix op: {c}", .{op}),
    };
}

pub fn infix(op: char) ?BindingPower {
    return switch (op) {
        '=' => .{ .left = 2, .right = 1 },
        '?' => .{ .left = 4, .right = 3 },
        '+', '-' => .{ .left = 5, .right = 6 },
        '*', '/' => .{ .left = 7, .right = 8 },
        else => null,
    };
}

pub fn postfix(op: char) ?BindingPower {
    return switch (op) {
        '!' => .{ .left = 11, .right = 0 },
        '[' => .{ .left = 13, .right = 0 },
        else => null,
    };
}

const std = @import("std");
const char = u8;
const string = []const char;
const BindingPower = @This();
