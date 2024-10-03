pub fn main() !void {
    const input = "a = 0 ? (6 * 9) : c = d";
    const ast = try Ast.init(std.heap.page_allocator, input);
    for (ast.nodes, 0..) |n, i| {
        std.debug.print("[{d}] {c}", .{
            i,
            n.ch,
        });

        for (0..n.args_n) |offset| {
            if (offset == 0) std.debug.print(" : ", .{});
            std.debug.print("{d},", .{ast.args[n.args_start.args + offset].nodes});
        }
        std.debug.print("\n", .{});
    }
}

const Node = struct {
    ch: char,
    args_n: u8,
    //if args_start == 3
    //  args[Index] = first arg
    //  args[Index] + 1 = second arg
    //  args[Index + 1] = third arg
    //else
    //  nodes[Index] = first arg
    //  nodes[Index + 1] = second arg
    args_start: Parser.Index,

    comptime {
        if (builtin.mode == .ReleaseFast)
            assert(@sizeOf(Node) == 8);
        if (builtin.mode == .Debug)
            assert(@sizeOf(Node) == 12);
    }

    fn init(ch: char, args_n: u8, args_start: Parser.Index) Node {
        switch (args_n) {
            0 => {},
            3 => _ = args_start.args,
            else => _ = args_start.nodes,
        }
        return .{
            .ch = ch,
            .args_n = args_n,
            .args_start = args_start,
        };
    }
};

const Parser = struct {
    allocator: Allocator,
    tokens: []const Token,
    tok_i: usize,
    nodes: DynamicArray(Node),
    args: DynamicArray(Index),

    const Index = union {
        nodes: u32,
        args: u32,

        comptime {
            if (builtin.mode == .ReleaseFast)
                assert(@sizeOf(Index) == 4);
            if (builtin.mode == .Debug)
                assert(@sizeOf(Index) == 8);
        }
    };

    fn parse(p: *Parser) !void {
        _ = try p.parse_node(0);
    }

    fn parse_node(p: *Parser, bp_min: u8) !Index {
        const left_i = try p.nodes_reserve();

        var left: Node = switch (p.next_tok()) {
            .atom => |ch| Node.init(ch, 0, undefined),
            .op => |op| blk: {
                switch (op) {
                    '(' => {
                        p.nodes.items.len -= 1;
                        const new_left_i = try p.parse_node(0);
                        assert(p.next_tok().op == ')');
                        break :blk p.nodes.items[new_left_i.nodes];
                    },
                    else => {
                        const bp = BindingPower.prefix(op);
                        const right_i = try p.parse_node(bp.right);
                        break :blk Node.init(op, 1, right_i);
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

                const start_i = try p.nodes_append(left);

                var args_n: u8 = 1;
                if (op == '[') {
                    _ = try p.parse_node(bp.right);
                    assert(p.next_tok().op == ']');
                    args_n += 1;
                }

                left = Node.init(op, args_n, start_i);
                continue;
            }
            if (BindingPower.infix(op)) |bp| {
                if (bp.left < bp_min) break;
                _ = p.next_tok();

                const start_i = try p.nodes_append(left);
                var start = start_i;

                var args_n: u8 = 2;
                if (op == '?') {
                    _ = try p.parse_node(0);
                    assert(p.next_tok().op == ':');
                    args_n += 1;
                }
                const last_i = try p.parse_node(bp.right);

                if (args_n == 3) {
                    start = try p.args_append(start_i);
                    _ = try p.args_append(last_i);
                }

                left = Node.init(op, args_n, start);
                continue;
            }
            break;
        }

        p.nodes.items[left_i.nodes] = left;
        return left_i;
    }

    fn next_tok(p: *Parser) Token {
        p.tok_i += 1;
        return p.tokens[p.tok_i - 1];
    }

    fn peek_tok(p: Parser) Token {
        return p.tokens[p.tok_i];
    }

    fn nodes_reserve(p: *Parser) !Index {
        try p.nodes.resize(p.allocator, p.nodes.items.len + 1);
        return .{ .nodes = @intCast(p.nodes.items.len - 1) };
    }

    fn nodes_append(p: *Parser, node: Node) !Index {
        try p.nodes.append(p.allocator, node);
        return .{ .nodes = @intCast(p.nodes.items.len - 1) };
    }

    fn args_append(p: *Parser, i: Index) !Index {
        try p.args.append(p.allocator, i);
        return .{ .args = @intCast(p.args.items.len - 1) };
    }
};

pub const Ast = struct {
    nodes: []const Node,
    args: []const Parser.Index,

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
            .nodes = .{},
            .args = .{},
        };

        try parser.parse();

        return .{
            .nodes = try parser.nodes.toOwnedSlice(allocator),
            .args = try parser.args.toOwnedSlice(allocator),
        };
    }

    pub fn encode(a: Ast, allocator: Allocator) !string {
        var str = DynamicArray(char){};
        try a.encode_node(0, str.writer(allocator).any());
        return try str.toOwnedSlice(allocator);
    }

    fn encode_node(a: Ast, i: usize, writer: std.io.AnyWriter) !void {
        const node = a.nodes[i];
        switch (node.args_n) {
            0 => try writer.writeByte(node.ch),
            3 => {
                try writer.print("({c}", .{node.ch});

                const first_i = a.args[node.args_start.args].nodes;
                try writer.writeByte(' ');
                try a.encode_node(first_i, writer);

                const second_i = first_i + 1;
                try writer.writeByte(' ');
                try a.encode_node(second_i, writer);

                const third_i = a.args[node.args_start.args + 1].nodes;
                try writer.writeByte(' ');
                try a.encode_node(third_i, writer);

                try writer.writeByte(')');
            },
            else => {
                try writer.print("({c}", .{node.ch});
                for (0..node.args_n) |offset| {
                    const arg_i = node.args_start.nodes + offset;
                    assert(arg_i != i);
                    try writer.writeByte(' ');
                    try a.encode_node(arg_i, writer);
                }
                try writer.writeByte(')');
            },
        }
        if (node.args_n == 0) {} else {}
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

    try test_parse(
        allocator,
        "a ? (b * c) : d",
        "(? a (* b c) d)",
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
