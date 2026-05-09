const std = @import("std");
const xitlog = @import("xitlog");

test "generate html" {
    const allocator = std.testing.allocator;

    var root = xitlog.Widget{ .widget_list = try xitlog.WidgetList.init(allocator) };
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
