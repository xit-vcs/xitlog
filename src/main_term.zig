const std = @import("std");
const builtin = @import("builtin");
const xitlog = @import("xitlog");
const xitui = xitlog.xitui;
const term = xitui.terminal;
const layout = xitui.layout;
const Grid = xitui.grid.Grid;

const feed_xml = @embedFile("embed/feed.xml");

pub fn main() !void {
    // init allocator
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = if (builtin.mode == .Debug) debug_allocator.allocator() else std.heap.smp_allocator;
    defer if (builtin.mode == .Debug) {
        _ = debug_allocator.deinit();
    };

    // init io
    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();
    var feed = try xitlog.Feed.parse(allocator, feed_xml);
    defer feed.deinit();

    // init root widget
    const blog_page = try xitlog.BlogPage.initIndex(allocator, feed);
    var root = xitlog.Widget{
        .scroll = try xitui.widget.Scroll(xitlog.Widget).init(allocator, .{ .blog_page = blog_page }, .vert),
    };
    defer root.deinit();

    // set initial focus for root widget
    try root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());
    if (root.getFocus().child_id) |child_id| {
        try root.getFocus().setFocus(child_id);
    }

    // init term
    var terminal = try term.Terminal.init(io, allocator);
    defer terminal.deinit(io);

    var last_size = layout.Size{ .width = 0, .height = 0 };
    var last_grid = try Grid.init(allocator, last_size);
    defer last_grid.deinit();

    while (!term.quit) {
        // render to tty
        try terminal.render(&root, &last_grid, &last_size);

        // process any inputs
        while (try terminal.readKey(io)) |key| {
            switch (key) {
                .codepoint => |cp| if (cp == 'q') return,
                else => {},
            }
            try root.input(key, root.getFocus());
        }

        // rebuild widget
        try root.build(.{
            .min_size = .{ .width = null, .height = null },
            .max_size = .{ .width = last_size.width, .height = last_size.height },
        }, root.getFocus());

        // TODO: do variable sleep with target frame rate
        try std.Io.sleep(io, .fromMilliseconds(5), .real);
    }
}
