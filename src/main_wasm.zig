const std = @import("std");
const xitlog = @import("xitlog");
const xitui = xitlog.xitui;
const inp = xitui.input;

const allocator = std.heap.wasm_allocator;
const feed_xml = @embedFile("assets/feed.xml");

var root: ?xitlog.Widget = null;

fn renderPage(page_name: []const u8, push_history: bool) !void {
    var feed = try xitlog.Feed.parse(allocator, feed_xml);
    defer feed.deinit();

    var next_root = if (std.mem.eql(u8, page_name, "index"))
        xitlog.Widget{ .blog_page = try xitlog.BlogPage.initIndex(allocator, feed) }
    else
        xitlog.Widget{ .blog_page = try xitlog.BlogPage.initPost(allocator, feed, page_name) };
    errdefer next_root.deinit();

    try next_root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, next_root.getFocus());

    if (root) |*old_root| old_root.deinit();
    root = next_root;

    try updateHtml();

    if (push_history) {
        const path = if (std.mem.eql(u8, page_name, "index"))
            try allocator.dupe(u8, "index.html")
        else
            try std.fmt.allocPrint(allocator, "{s}.html", .{page_name});
        defer allocator.free(path);
        pushUrl(path);
    }
}

fn updateHtml() !void {
    const root_ptr = if (root) |*root_value| root_value else return error.NotStarted;
    const html = try xitlog.generateHtml(allocator, root_ptr);
    defer allocator.free(html);
    setHtml(html);
}

fn start() !void {
    try renderPage("index", false);
}

fn tick() !void {
    const root_ptr = if (root) |*root_value| root_value else return error.NotStarted;

    try root_ptr.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root_ptr.getFocus());

    try updateHtml();
}

fn onKeyDown(key_code: u32) !void {
    const root_ptr = if (root) |*root_value| root_value else return error.NotStarted;
    const key: inp.Key = switch (key_code) {
        38 => .arrow_up,
        40 => .arrow_down,
        else => return,
    };
    try root_ptr.input(key, root_ptr.getFocus());
}

fn normalizePageName(raw: []const u8) []const u8 {
    var page_name = raw;
    if (std.mem.indexOfScalar(u8, page_name, '#')) |hash_index| page_name = page_name[0..hash_index];
    if (std.mem.indexOfScalar(u8, page_name, '?')) |query_index| page_name = page_name[0..query_index];
    if (std.mem.lastIndexOfScalar(u8, page_name, '/')) |slash_index| page_name = page_name[slash_index + 1 ..];
    if (std.mem.endsWith(u8, page_name, ".html")) page_name = page_name[0 .. page_name.len - ".html".len];
    if (page_name.len == 0) return "index";
    return page_name;
}

fn consoleLog(arg: []const u8) void {
    _consoleLog(arg.ptr, @intCast(arg.len));
}

fn setHtml(arg: []const u8) void {
    _setHtml(arg.ptr, @intCast(arg.len));
}

fn pushUrl(arg: []const u8) void {
    _pushUrl(arg.ptr, @intCast(arg.len));
}

extern fn _consoleLog(arg: [*]const u8, len: u32) void;
extern fn _setHtml(arg: [*]const u8, len: u32) void;
extern fn _pushUrl(arg: [*]const u8, len: u32) void;

export fn _alloc(len: u32) u32 {
    const bytes = allocator.alloc(u8, len) catch return 0;
    return @intCast(@intFromPtr(bytes.ptr));
}

export fn _free(ptr: u32, len: u32) void {
    const bytes: [*]u8 = @ptrFromInt(ptr);
    allocator.free(bytes[0..len]);
}

export fn _start() void {
    start() catch |err| {
        var buf: [256]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "start: {}", .{err}) catch unreachable;
        consoleLog(str);
    };
}

export fn _tick() bool {
    tick() catch |err| {
        var buf: [256]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "tick: {}", .{err}) catch unreachable;
        consoleLog(str);
        return false;
    };
    return true;
}

export fn _onKeyDown(key_code: u32) void {
    onKeyDown(key_code) catch consoleLog("error");
}

export fn _navigate(ptr: u32, len: u32, push_history: bool) bool {
    const bytes: [*]const u8 = @ptrFromInt(ptr);
    const page_name = normalizePageName(bytes[0..len]);
    renderPage(page_name, push_history) catch |err| {
        var buf: [256]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "navigate: {}", .{err}) catch unreachable;
        consoleLog(str);
        return false;
    };
    return true;
}
