const std = @import("std");
const builtin = @import("builtin");
const xitui = @import("xitui");
const term = xitui.terminal;
const wgt = xitui.widget;
const layout = xitui.layout;
const inp = xitui.input;
const Grid = xitui.grid.Grid;
const Focus = xitui.focus.Focus;

const ExportedFunctions = if (builtin.cpu.arch == .wasm32)
    struct {
        extern fn consoleLog(arg: [*]const u8, len: u32) void;
        extern fn setHtml(arg: [*]const u8, len: u32) void;
        extern fn addElem(arg: [*]const u8, len: u32, id: u32, x: u32, y: u32, width: u32, height: u32) void;

        var buffer: [512 * 1024]u8 = undefined; // 512KB static buffer

        fn start() void {
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const html = generateHtml(fba.allocator()) catch |err| switch (err) {
                error.OutOfMemory => {
                    consoleLogZ("out of memory");
                    return;
                },
                else => {
                    consoleLogZ("error");
                    return;
                },
            };
            setHtmlZ(html);
        }

        fn consoleLogZ(arg: []const u8) void {
            consoleLog(arg.ptr, @intCast(arg.len));
        }

        fn setHtmlZ(arg: []const u8) void {
            setHtml(arg.ptr, @intCast(arg.len));
        }

        fn addElemZ(arg: []const u8, id: u32, x: u32, y: u32, width: u32, height: u32) void {
            addElem(arg.ptr, @intCast(arg.len), id, x, y, width, height);
        }
    }
else
    struct {};

export fn start() void {
    if (builtin.cpu.arch == .wasm32) {
        ExportedFunctions.start();
    }
}

pub fn generateHtml(allocator: std.mem.Allocator) ![]const u8 {
    // init root widget
    var root = Widget{ .widget_list = try WidgetList.init(allocator) };
    defer root.deinit();

    // set initial focus for root widget
    try root.build(.{
        .min_size = .{ .width = null, .height = null },
        .max_size = .{ .width = null, .height = null },
    }, root.getFocus());
    if (root.getFocus().child_id) |child_id| {
        try root.getFocus().setFocus(child_id);
    }

    var output = std.ArrayList([]const u8){};
    defer output.deinit(allocator);

    const grid_str = try root.getGrid().?.toString(allocator);
    defer allocator.free(grid_str);

    try output.append(allocator, grid_str);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var iter = root.getFocus().children.iterator();
    while (iter.next()) |entry| {
        const child = entry.value_ptr.*;
        switch (child.focus.kind) {
            .text_box => {
                const html = try std.fmt.allocPrint(
                    arena.allocator(),
                    "<div class='{s}' style='position: absolute; top: {}px; left: {}px; width: {}px; height: {}px;'></div>",
                    .{
                        @tagName(child.focus.kind),
                        (child.rect.y + 1) * 22,
                        (child.rect.x + 1) * 12,
                        (child.rect.size.width - 2) * 12,
                        (child.rect.size.height - 2) * 22,
                    },
                );
                try output.append(allocator, html);
            },
            else => {},
        }
    }

    return try std.mem.join(allocator, "", output.items);
}

const Widget = union(enum) {
    text: wgt.Text(Widget),
    box: wgt.Box(Widget),
    text_box: wgt.TextBox(Widget),
    scroll: wgt.Scroll(Widget),
    widget_list: WidgetList,

    pub fn deinit(self: *Widget) void {
        switch (self.*) {
            inline else => |*case| case.deinit(),
        }
    }

    pub fn build(self: *Widget, constraint: layout.Constraint, root_focus: *Focus) anyerror!void {
        switch (self.*) {
            inline else => |*case| try case.build(constraint, root_focus),
        }
    }

    pub fn input(self: *Widget, key: inp.Key, root_focus: *Focus) anyerror!void {
        switch (self.*) {
            inline else => |*case| try case.input(key, root_focus),
        }
    }

    pub fn clearGrid(self: *Widget) void {
        switch (self.*) {
            inline else => |*case| case.clearGrid(),
        }
    }

    pub fn getGrid(self: Widget) ?Grid {
        switch (self) {
            inline else => |*case| return case.getGrid(),
        }
    }

    pub fn getFocus(self: *Widget) *Focus {
        switch (self.*) {
            inline else => |*case| return case.getFocus(),
        }
    }
};

const WidgetList = struct {
    allocator: std.mem.Allocator,
    scroll: wgt.Scroll(Widget),

    pub fn init(allocator: std.mem.Allocator) !WidgetList {
        var self = blk: {
            var inner_box = try wgt.Box(Widget).init(allocator, null, .vert);
            errdefer inner_box.deinit();

            var scroll = try wgt.Scroll(Widget).init(allocator, .{ .box = inner_box }, .vert);
            errdefer scroll.deinit();

            break :blk WidgetList{
                .allocator = allocator,
                .scroll = scroll,
            };
        };
        errdefer self.deinit();

        const inner_box = &self.scroll.child.box;

        {
            var text_box = try wgt.TextBox(Widget).init(allocator, "this is a TextBox", .single, .none);
            errdefer text_box.deinit();
            text_box.getFocus().focusable = true;
            try inner_box.children.put(text_box.getFocus().id, .{ .widget = .{ .text_box = text_box }, .rect = null, .min_size = null });
        }

        {
            var text_box = try wgt.TextBox(Widget).init(allocator, "this is a\nmulti-line TextBox", .single, .none);
            errdefer text_box.deinit();
            text_box.getFocus().focusable = true;
            try inner_box.children.put(text_box.getFocus().id, .{ .widget = .{ .text_box = text_box }, .rect = null, .min_size = null });
        }

        if (inner_box.children.count() > 0) {
            self.scroll.getFocus().child_id = inner_box.children.keys()[0];
        }

        return self;
    }

    pub fn deinit(self: *WidgetList) void {
        self.scroll.deinit();
    }

    pub fn build(self: *WidgetList, constraint: layout.Constraint, root_focus: *Focus) !void {
        self.clearGrid();
        const children = &self.scroll.child.box.children;
        for (children.keys(), children.values()) |id, *commit| {
            commit.widget.text_box.border_style = if (self.getFocus().child_id == id)
                (if (root_focus.grandchild_id == id) .double else .single)
            else
                .hidden;
        }
        try self.scroll.build(constraint, root_focus);
    }

    pub fn input(self: *WidgetList, key: inp.Key, root_focus: *Focus) !void {
        _ = .{ self, key, root_focus };
    }

    pub fn clearGrid(self: *WidgetList) void {
        self.scroll.clearGrid();
    }

    pub fn getGrid(self: WidgetList) ?Grid {
        return self.scroll.getGrid();
    }

    pub fn getFocus(self: *WidgetList) *Focus {
        return self.scroll.getFocus();
    }

    pub fn getSelectedIndex(self: WidgetList) ?usize {
        if (self.scroll.child.box.focus.child_id) |child_id| {
            const children = &self.scroll.child.box.children;
            return children.getIndex(child_id);
        } else {
            return null;
        }
    }

    fn updateScroll(self: *WidgetList, index: usize) void {
        const left_box = &self.scroll.child.box;
        if (left_box.children.values()[index].rect) |rect| {
            self.scroll.scrollToRect(rect);
        }
    }
};
