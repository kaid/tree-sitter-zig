const testing = @import("std").testing;

const root = @import("tree-sitter-zig");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

test "can load grammar" {
    const parser = c.ts_parser_new().?;
    defer c.ts_parser_delete(parser);

    const lang: *const c.TSLanguage = @ptrCast(@alignCast(root.language()));
    try testing.expect(c.ts_parser_set_language(parser, lang));
    try testing.expectEqual(lang, c.ts_parser_language(parser).?);
}
