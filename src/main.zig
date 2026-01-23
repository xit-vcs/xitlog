const std = @import("std");
const xitui = @import("xitui");
const term = xitui.terminal;
const wgt = xitui.widget;
const layout = xitui.layout;
const inp = xitui.input;
const Grid = xitui.grid.Grid;
const Focus = xitui.focus.Focus;

export fn start() void {
    startZ() catch |err| switch (err) {
        error.OutOfMemory => {
            consoleLogZ("out of memory");
            return;
        },
        else => {
            consoleLogZ("error");
            return;
        },
    };
}

extern fn consoleLog(arg: [*]const u8, len: u32) void;
extern fn setHtml(arg: [*]const u8, len: u32) void;
extern fn addElem(arg: [*]const u8, len: u32, id: u32, x: u32, y: u32, width: u32, height: u32) void;

fn consoleLogZ(arg: []const u8) void {
    consoleLog(arg.ptr, arg.len);
}

fn setHtmlZ(arg: []const u8) void {
    setHtml(arg.ptr, arg.len);
}

fn addElemZ(arg: []const u8, id: u32, x: u32, y: u32, width: u32, height: u32) void {
    addElem(arg.ptr, arg.len, id, x, y, width, height);
}

var buffer: [512 * 1024]u8 = undefined; // 512KB static buffer

fn startZ() !void {
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

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

    const grid_str = try root.getGrid().?.toString(allocator);
    defer allocator.free(grid_str);

    setHtmlZ(grid_str);

    var iter = root.getFocus().children.iterator();
    while (iter.next()) |entry| {
        const child = entry.value_ptr.*;
        addElemZ(@tagName(child.focus.kind), child.focus.id, child.rect.x, child.rect.y, child.rect.size.width, child.rect.size.height);
    }
}

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
        if (self.getFocus().child_id) |child_id| {
            const children = &self.scroll.child.box.children;
            if (children.getIndex(child_id)) |current_index| {
                var index = current_index;

                switch (key) {
                    .arrow_up => {
                        index -|= 1;
                    },
                    .arrow_down => {
                        if (index + 1 < children.count()) {
                            index += 1;
                        }
                    },
                    .home => {
                        index = 0;
                    },
                    .end => {
                        if (children.count() > 0) {
                            index = children.count() - 1;
                        }
                    },
                    .page_up => {
                        if (self.getGrid()) |grid| {
                            const half_count = (grid.size.height / 3) / 2;
                            index -|= half_count;
                        }
                    },
                    .page_down => {
                        if (self.getGrid()) |grid| {
                            if (children.count() > 0) {
                                const half_count = (grid.size.height / 3) / 2;
                                index = @min(index + half_count, children.count() - 1);
                            }
                        }
                    },
                    else => {},
                }

                if (index != current_index) {
                    try root_focus.setFocus(children.keys()[index]);
                    self.updateScroll(index);
                }
            }
        }
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

pub const Widget = union(enum) {
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
