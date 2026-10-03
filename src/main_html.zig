const std = @import("std");
const builtin = @import("builtin");
const xitlog = @import("xitlog");

const feed_xml = @embedFile("embed/feed.xml");
const template = @embedFile("embed/index.html");

pub fn main() !void {
    var safe_allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    const allocator = if (builtin.optimize == .debug) safe_allocator.allocator() else std.heap.smp_allocator;
    defer if (builtin.optimize == .debug) {
        _ = safe_allocator.deinit();
    };

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    var feed = try xitlog.Feed.parse(allocator, feed_xml);
    defer feed.deinit();

    {
        const html = try xitlog.generatePageHtml(allocator, template, feed, "index");
        defer allocator.free(html);
        try cwd.writeFile(io, .{ .sub_path = "html/index.html", .data = html });
    }

    for (feed.entries) |entry| {
        const html = try xitlog.generatePageHtml(allocator, template, feed, entry.slug);
        defer allocator.free(html);
        const path = try allocator.print("html/{s}.html", .{entry.slug});
        defer allocator.free(path);
        try cwd.writeFile(io, .{ .sub_path = path, .data = html });
    }
}
