const std = @import("std");
const builtin = @import("builtin");
const xitlog = @import("xitlog");
const xitui = xitlog.xitui;
const term = xitui.terminal;

const feed_xml = @embedFile("embed/feed.xml");

pub fn main() !void {
    // init allocator
    var safe_allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    const allocator = if (builtin.optimize == .debug) safe_allocator.allocator() else std.heap.smp_allocator;
    defer if (builtin.optimize == .debug) {
        _ = safe_allocator.deinit();
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
        .scroll = try xitui.widget.Scroll(xitlog.Widget).init(allocator, .{ .blog_page = blog_page }, .{ .direction = .vert }),
    };
    defer root.deinit(allocator);

    // set initial focus for root widget
    try root.build(allocator, .{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());
    if (root.getFocus().child_id) |child_id| {
        root.getFocus().setFocus(child_id);
    }

    // init term
    var terminal = try term.Terminal.init(io, allocator);
    defer terminal.deinit(io);

    // set term as active so it will be properly cooked
    // when a panic/segfault happens
    term.setActive(&terminal);
    defer term.setActive(null);

    while (!term.quit.load(.monotonic)) {
        // render to tty
        const grid_changed = try terminal.render(&root);

        // process any inputs. if the grid didn't change, block
        // on the first read so the thread sleeps until input arrives.
        var blocking = !grid_changed;
        while (try terminal.readKey(io, blocking)) |key| {
            blocking = false;
            switch (key) {
                .codepoint => |cp| if (cp == 'q') return,
                else => {},
            }
            try root.input(allocator, key, root.getFocus());
        }

        // rebuild widget
        try root.build(allocator, .{
            .min_size = .{ .width = null, .height = null },
            .max_size = .{ .width = terminal.size.width, .height = terminal.size.height },
        }, root.getFocus());
    }
}
