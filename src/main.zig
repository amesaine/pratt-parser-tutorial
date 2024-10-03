pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const max_size = 36;
    var input = try DynamicArray(char).initCapacity(allocator, max_size);

    const mock = try std.fs.cwd().openFile("src/mock.txt", .{});
    var buf = std.io.bufferedReader(mock.reader());
    var reader = buf.reader();

    const iterations = 10000;
    while (reader.streamUntilDelimiter(input.writer(allocator), '\n', null)) {
        for (0..iterations) |_| {
            const ast = try Ast.init(allocator, input.items);
            _ = try ast.encode(allocator);
        }
        input.clearRetainingCapacity();
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const DynamicArray = std.ArrayListUnmanaged;

// const Ast = @import("1_parser.zig").Ast;
// const Ast = @import("2_parser_slice.zig").Ast;
// const Ast = @import("3_parser_dod.zig").Ast;
const Ast = @import("4_parser_final.zig").Ast;

const string = []const u8;
const char = u8;
