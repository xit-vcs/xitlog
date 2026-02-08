const std = @import("std");
const xitlog = @import("xitlog");

test "generate html" {
    const allocator = std.testing.allocator;
    const html = try xitlog.generateHtml(allocator);
    defer allocator.free(html);
}
