const std = @import("std");
const xitlog = @import("xitlog");
const xitui = xitlog.xitui;
const inp = xitui.input;

const allocator = std.heap.wasm_allocator;

var root: xitlog.Widget = undefined;

fn start() !void {
    // init root widget
    root = xitlog.Widget{ .widget_list = try xitlog.WidgetList.init(allocator) };
    errdefer root.deinit();

    // set initial focus for root widget
    try root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());
    if (root.getFocus().child_id) |child_id| {
        try root.getFocus().setFocus(child_id);
    }

    // set the html
    const html = try xitlog.generateHtml(allocator, &root);
    defer allocator.free(html);
    setHtml(html);
}

fn tick() !void {
    // rebuild widget
    try root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());

    // set the html
    const html = try xitlog.generateHtml(allocator, &root);
    defer allocator.free(html);
    setHtml(html);
}

fn onKeyDown(key_code: u32) !void {
    const key: inp.Key = switch (key_code) {
        38 => .arrow_up,
        40 => .arrow_down,
        else => return,
    };
    try root.input(key, root.getFocus());
}

fn consoleLog(arg: []const u8) void {
    _consoleLog(arg.ptr, @intCast(arg.len));
}

fn setHtml(arg: []const u8) void {
    _setHtml(arg.ptr, @intCast(arg.len));
}

extern fn _consoleLog(arg: [*]const u8, len: u32) void;
extern fn _setHtml(arg: [*]const u8, len: u32) void;

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
