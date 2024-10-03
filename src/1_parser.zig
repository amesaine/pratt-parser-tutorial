pub fn main() !void {
    const ast = try Ast.init(std.heap.page_allocator, "");
    _ = try ast.encode(std.heap.page_allocator);
    try test_parse(std.heap.page_allocator, "", "");
}

const Node = struct {
    ch: char,
    args: ?Arguments,

    comptime {
        if (builtin.cpu.arch == .x86) assert(@sizeOf(Node) == 20);
        if (builtin.cpu.arch == .x86_64) assert(@sizeOf(Node) == 40);
    }

    const Arguments = struct {
        left: ?*Node,
        middle: ?*Node,
        right: ?*Node,
    };
};

const Parser = struct {
    allocator: Allocator,
    tokens: []const Token,
    tok_i: usize,
    root: *Node,

    fn parse(p: *Parser) !void {
        p.root = try p.parse_node(0);
    }

    fn parse_node(p: *Parser, bp_min: u8) !*Node {
        var left_ptr = try p.allocator.create(Node);
        left_ptr.* = switch (p.next_tok()) {
            .atom => |ch| .{ .ch = ch, .args = null },
            .op => |op| blk: {
                switch (op) {
                    '(' => {
                        const new_left = try p.parse_node(0);
                        assert(p.next_tok().op == ')');
                        break :blk new_left.*;
                    },
                    else => {
                        const bp = BindingPower.prefix(op);
                        const right_ptr = try p.parse_node(bp.right);

                        const args: Node.Arguments = .{
                            .left = null,
                            .middle = null,
                            .right = right_ptr,
                        };
                        break :blk .{ .ch = op, .args = args };
                    },
                }
            },
            .eof => std.debug.panic("Unexpected EOF", .{}),
        };

        while (p.peek_tok() != .eof) {
            assert(p.peek_tok() == .op);
            const op = p.peek_tok().op;

            if (BindingPower.postfix(op)) |bp| {
                if (bp.left < bp_min) break;
                _ = p.next_tok();

                var args: Node.Arguments = .{
                    .left = left_ptr,
                    .middle = null,
                    .right = null,
                };
                if (op == '[') {
                    const right_ptr = try p.parse_node(bp.right);
                    assert(p.next_tok().op == ']');
                    args.right = right_ptr;
                }

                const postfix_ptr = try p.allocator.create(Node);
                postfix_ptr.* = .{ .ch = op, .args = args };
                left_ptr = postfix_ptr;
                continue;
            }
            if (BindingPower.infix(op)) |bp| {
                if (bp.left < bp_min) break;
                _ = p.next_tok();

                var args: Node.Arguments = .{
                    .left = left_ptr,
                    .middle = null,
                    .right = undefined,
                };
                if (op == '?') {
                    const middle_ptr = try p.parse_node(0);
                    assert(p.next_tok().op == ':');
                    args.middle = middle_ptr;
                }
                const right_ptr = try p.parse_node(bp.right);
                args.right = right_ptr;

                const infix_ptr = try p.allocator.create(Node);
                infix_ptr.* = .{ .ch = op, .args = args };
                left_ptr = infix_ptr;
                continue;
            }
            break;
        }

        return left_ptr;
    }

    fn next_tok(p: *Parser) Token {
        p.tok_i += 1;
        return p.tokens[p.tok_i - 1];
    }

    fn peek_tok(p: Parser) Token {
        return p.tokens[p.tok_i];
    }
};

pub const Ast = struct {
    root: *Node,

    pub fn init(allocator: Allocator, input: string) !Ast {
        var tokens = DynamicArray(Token){};
        var lexer = Lexer{ .input = input, .i = 0 };
        while (true) {
            const tok = lexer.next();
            try tokens.append(allocator, tok);
            if (tok == .eof) break;
        }

        var parser = Parser{
            .allocator = allocator,
            .tokens = try tokens.toOwnedSlice(allocator),
            .tok_i = 0,
            .root = undefined,
        };

        try parser.parse();

        return Ast{ .root = parser.root };
    }

    pub fn encode(a: Ast, allocator: Allocator) !string {
        var str = DynamicArray(char){};
        try encode_node(a.root.*, str.writer(allocator).any());
        return try str.toOwnedSlice(allocator);
    }

    fn encode_node(node: Node, writer: std.io.AnyWriter) !void {
        if (node.args == null) {
            try writer.writeByte(node.ch);
            return;
        }

        try writer.print("({c}", .{node.ch});
        if (node.args.?.left) |left| {
            try writer.writeByte(' ');
            try encode_node(left.*, writer);
        }
        if (node.args.?.middle) |middle| {
            try writer.writeByte(' ');
            try encode_node(middle.*, writer);
        }
        if (node.args.?.right) |right| {
            try writer.writeByte(' ');
            try encode_node(right.*, writer);
        }
        try writer.writeByte(')');
    }
};

fn test_parse(allocator: Allocator, input: string, expected: string) !void {
    const ast = try Ast.init(allocator, input);
    const actual = try ast.encode(allocator);

    try std.testing.expectEqualStrings(expected, actual);
}

test "atom" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        " 1 ",
        "1",
    );
}

test "binary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        "1 + 2",
        "(+ 1 2)",
    );

    try test_parse(
        allocator,
        "1 + 2 + 3",
        "(+ (+ 1 2) 3)",
    );

    try test_parse(
        allocator,
        "1 + 2 - 3",
        "(- (+ 1 2) 3)",
    );

    try test_parse(
        allocator,
        "1 + 2 - 3 * 4",
        "(- (+ 1 2) (* 3 4))",
    );

    try test_parse(
        allocator,
        "x = 1 + 2 - 3 * 4 = y",
        "(= x (= (- (+ 1 2) (* 3 4)) y))",
    );
}

test "unary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        "-1",
        "(- 1)",
    );

    try test_parse(
        allocator,
        "3 * -4",
        "(* 3 (- 4))",
    );

    try test_parse(
        allocator,
        "-6!",
        "(- (! 6))",
    );

    try test_parse(
        allocator,
        "a[i]",
        "([ a i)",
    );
}

test "delimiter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        "1 + (2 - 3) * 4",
        "(+ 1 (* (- 2 3) 4))",
    );
}

test "ternary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        "a ? b : c",
        "(? a b c)",
    );
}

test "final" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try test_parse(
        allocator,
        "x[i] = -1! + (2 - 3) * 4 ? z : 0 = y",
        "(= ([ x i) (= (? (+ (- (! 1)) (* (- 2 3) 4)) z 0) y))",
    );
}

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const DynamicArray = std.ArrayListUnmanaged;
const builtin = @import("builtin");

const Lexer = @import("lexer.zig");
const Token = Lexer.Token;
const BindingPower = @import("binding_power.zig");

const string = []const u8;
const char = u8;
