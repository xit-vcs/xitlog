const std = @import("std");
const xitlog = @import("xitlog");

const feed_xml = @embedFile("assets/feed.xml");

test "generate html" {
    const allocator = std.testing.allocator;

    var feed = try xitlog.Feed.parse(allocator, feed_xml);
    defer feed.deinit();

    var root = xitlog.Widget{ .blog_page = try xitlog.BlogPage.initIndex(allocator, feed) };
    defer root.deinit();

    // set initial focus for root widget
    try root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());
    if (root.getFocus().child_id) |child_id| {
        try root.getFocus().setFocus(child_id);
    }

    const html = try xitlog.generateHtml(allocator, &root);
    defer allocator.free(html);
}
