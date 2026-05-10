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

test "parse feed xml with comments, cdata, and quoted attributes" {
    const allocator = std.testing.allocator;
    const xml =
        \\<?xml version="1.0"?>
        \\<feed>
        \\  <!-- ignored -->
        \\  <entry>
        \\    <title>one &amp; two</title>
        \\    <link href="https://example.invalid/post.html" title='post-slug'/>
        \\    <updated>2026-05-10T00:00:00Z</updated>
        \\    <content type="html"><![CDATA[<p>hello <strong>world</strong></p>]]></content>
        \\  </entry>
        \\</feed>
    ;

    var feed = try xitlog.Feed.parse(allocator, xml);
    defer feed.deinit();

    try std.testing.expectEqual(@as(usize, 1), feed.entries.len);
    try std.testing.expectEqualStrings("one & two", feed.entries[0].title);
    try std.testing.expectEqualStrings("post-slug", feed.entries[0].slug);
    try std.testing.expectEqualStrings("2026-05-10T00:00:00Z", feed.entries[0].updated);
    try std.testing.expectEqualStrings("<p>hello <strong>world</strong></p>", feed.entries[0].content);
}
