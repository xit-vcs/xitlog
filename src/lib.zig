const std = @import("std");

pub const xitui = @import("xitui");
const wgt = xitui.widget;
const layout = xitui.layout;
const inp = xitui.input;
const Grid = xitui.grid.Grid;
const Focus = xitui.focus.Focus;

const max_line_len = 60;
const static_width = 80;
const dragon_ansi = @embedFile("assets/dragon.ansiwave");
const header =
    \\██╗  ██╗██╗████████╗██╗      ██████╗  ██████╗ 
    \\╚██╗██╔╝██║╚══██╔══╝██║     ██╔═══██╗██╔════╝ 
    \\ ╚███╔╝ ██║   ██║   ██║     ██║   ██║██║  ███╗
    \\ ██╔██╗ ██║   ██║   ██║     ██║   ██║██║   ██║
    \\██╔╝ ██╗██║   ██║   ███████╗╚██████╔╝╚██████╔╝
    \\╚═╝  ╚═╝╚═╝   ╚═╝   ╚══════╝ ╚═════╝  ╚═════╝ 
;

pub const Link = struct {
    href: []const u8,
};

pub const Entry = struct {
    title: []const u8,
    slug: []const u8,
    updated: []const u8,
    content: []const u8,

    fn deinit(self: Entry, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.slug);
        allocator.free(self.updated);
        allocator.free(self.content);
    }
};

pub const Feed = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,

    pub fn parse(allocator: std.mem.Allocator, xml: []const u8) !Feed {
        var entries: std.ArrayList(Entry) = .empty;
        errdefer {
            for (entries.items) |entry| entry.deinit(allocator);
            entries.deinit(allocator);
        }

        var rest = xml;
        while (findBetween(rest, "<entry>", "</entry>")) |entry_match| {
            const entry_xml = entry_match.inner;
            const title = try dupBetween(allocator, entry_xml, "<title>", "</title>");
            errdefer allocator.free(title);
            const updated = try dupBetween(allocator, entry_xml, "<updated>", "</updated>");
            errdefer allocator.free(updated);
            const content = try dupBetween(allocator, entry_xml, "<![CDATA[", "]]>");
            errdefer allocator.free(content);

            const link_tag = findTag(entry_xml, "link") orelse return error.MissingLink;
            const slug = try dupAttr(allocator, link_tag, "title");
            errdefer allocator.free(slug);

            try entries.append(allocator, .{
                .title = title,
                .slug = slug,
                .updated = updated,
                .content = content,
            });
            rest = entry_match.after;
        }

        return .{
            .allocator = allocator,
            .entries = try entries.toOwnedSlice(allocator),
        };
    }

    pub fn deinit(self: *Feed) void {
        for (self.entries) |entry| entry.deinit(self.allocator);
        self.allocator.free(self.entries);
    }

    pub fn findEntry(self: Feed, slug: []const u8) ?Entry {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.slug, slug)) return entry;
        }
        return null;
    }
};

const Match = struct {
    inner: []const u8,
    after: []const u8,
};

pub fn generatePageHtml(
    allocator: std.mem.Allocator,
    template: []const u8,
    feed: Feed,
    page_name: []const u8,
) ![]const u8 {
    var root = if (std.mem.eql(u8, page_name, "index"))
        Widget{ .blog_page = try BlogPage.initIndex(allocator, feed) }
    else
        Widget{ .blog_page = try BlogPage.initPost(allocator, feed, page_name) };
    defer root.deinit();

    try root.build(.{
        .min_size = .{ .width = static_width, .height = null },
        .max_size = .{ .width = static_width, .height = null },
    }, root.getFocus());

    const content = try generateHtml(allocator, &root);
    defer allocator.free(content);

    const title = if (std.mem.eql(u8, page_name, "index"))
        try allocator.dupe(u8, "XITLOG")
    else
        try pageTitle(allocator, page_name);
    defer allocator.free(title);

    const with_title = try replaceOnce(allocator, template, "{{{ XITLOG_TITLE }}}", title);
    defer allocator.free(with_title);
    return try replaceOnce(allocator, with_title, "{{{ XITLOG_CONTENT }}}", content);
}

pub fn generateHtml(allocator: std.mem.Allocator, root: *Widget) ![]const u8 {
    switch (root.*) {
        .blog_page => |*page| return try page.toHtml(allocator),
        else => {},
    }

    const grid = root.getGrid() orelse return error.MissingGrid;
    const links = root.getLinks();

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var link_index: usize = 0;
    var in_link = false;

    for (0..grid.size.height) |y| {
        for (0..grid.size.width) |x| {
            const rune = grid.cells.items[try grid.cells.at(.{ y, x })].rune orelse " ";
            if (!in_link and std.mem.eql(u8, rune, "[") and link_index < links.len) {
                try out.appendSlice(allocator, "<a href='");
                try appendEscapedAttr(allocator, &out, links[link_index].href);
                try out.appendSlice(allocator, "'>");
                in_link = true;
            } else if (in_link and std.mem.eql(u8, rune, "]")) {
                try out.appendSlice(allocator, "</a>");
                link_index += 1;
                in_link = false;
            } else {
                try appendEscapedHtml(allocator, &out, rune);
            }
        }
        try out.append(allocator, '\n');
    }

    if (in_link) try out.appendSlice(allocator, "</a>");
    return try out.toOwnedSlice(allocator);
}

pub const Widget = union(enum) {
    text: wgt.Text(Widget),
    box: wgt.Box(Widget),
    text_box: wgt.TextBox(Widget),
    scroll: wgt.Scroll(Widget),
    blog_page: BlogPage,

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

    pub fn getLinks(self: *Widget) []const Link {
        switch (self.*) {
            .blog_page => |*page| return page.links.items,
            else => return &.{},
        }
    }
};

pub const BlogPage = struct {
    const Line = struct {
        content: []const u8,
        raw_html: bool,
    };

    allocator: std.mem.Allocator,
    focus: Focus,
    grid: ?Grid,
    lines: std.ArrayList(Line),
    links: std.ArrayList(Link),

    pub fn initIndex(allocator: std.mem.Allocator, feed: Feed) !BlogPage {
        var page = BlogPage.empty(allocator);
        errdefer page.deinit();

        try page.addHeader(true);
        for (feed.entries) |entry| {
            const date = try formatDate(allocator, entry.updated);
            defer allocator.free(date);
            const href = try std.fmt.allocPrint(allocator, "{s}.html", .{entry.slug});
            errdefer allocator.free(href);
            try page.links.append(allocator, .{ .href = href });

            const line = try std.fmt.allocPrint(allocator, "[{s}] - {s}", .{ entry.title, date });
            defer allocator.free(line);
            try page.addWrappedText(line);
            try page.addLine("");
        }

        return page;
    }

    pub fn initPost(allocator: std.mem.Allocator, feed: Feed, slug: []const u8) !BlogPage {
        const entry = feed.findEntry(slug) orelse return error.PageNotFound;

        var page = BlogPage.empty(allocator);
        errdefer page.deinit();

        try page.addHeader(false);

        const date = try formatDate(allocator, entry.updated);
        defer allocator.free(date);
        const upper = try upperAsciiAlloc(allocator, entry.title);
        defer allocator.free(upper);
        const title_line = try std.fmt.allocPrint(allocator, "{s} - {s}", .{ upper, date });
        defer allocator.free(title_line);
        try page.addWrappedText(title_line);
        try page.addLine("");
        try page.addHtml(entry.content);

        return page;
    }

    fn empty(allocator: std.mem.Allocator) BlogPage {
        return .{
            .allocator = allocator,
            .focus = Focus.init(allocator, .container),
            .grid = null,
            .lines = .empty,
            .links = .empty,
        };
    }

    pub fn deinit(self: *BlogPage) void {
        self.focus.deinit();
        self.clearGrid();
        for (self.lines.items) |line| self.allocator.free(line.content);
        self.lines.deinit(self.allocator);
        for (self.links.items) |link| self.allocator.free(link.href);
        self.links.deinit(self.allocator);
    }

    pub fn build(self: *BlogPage, constraint: layout.Constraint, root_focus: *Focus) !void {
        _ = root_focus;
        self.clearGrid();

        const width = constraint.max_size.width orelse static_width;
        var grid = try Grid.init(self.allocator, .{
            .width = width,
            .height = @max(1, self.lines.items.len),
        });
        errdefer grid.deinit();

        for (self.lines.items, 0..) |line, y| {
            if (line.raw_html) continue;

            var utf8 = (try std.unicode.Utf8View.init(line.content)).iterator();
            var x: usize = 0;
            while (utf8.nextCodepointSlice()) |char| {
                if (x >= width) break;
                grid.cells.items[try grid.cells.at(.{ y, x })].rune = char;
                x += 1;
            }
        }

        self.grid = grid;
    }

    pub fn input(self: *BlogPage, key: inp.Key, root_focus: *Focus) !void {
        _ = self;
        _ = key;
        _ = root_focus;
    }

    pub fn clearGrid(self: *BlogPage) void {
        if (self.grid) |*grid| {
            grid.deinit();
            self.grid = null;
        }
    }

    pub fn getGrid(self: BlogPage) ?Grid {
        return self.grid;
    }

    pub fn getFocus(self: *BlogPage) *Focus {
        return &self.focus;
    }

    fn addHeader(self: *BlogPage, is_index: bool) !void {
        const home = if (is_index)
            "a blog about [xit]"
        else
            "[<- HOME] - a blog about [xit]";
        const home_href = if (is_index) "https://github.com/xit-vcs/xit" else "index.html";
        const xit_href = "https://github.com/xit-vcs/xit";
        const rss = "[RSS]";

        if (!is_index) try self.links.append(self.allocator, .{ .href = try self.allocator.dupe(u8, home_href) });
        try self.links.append(self.allocator, .{ .href = try self.allocator.dupe(u8, xit_href) });
        try self.links.append(self.allocator, .{ .href = try self.allocator.dupe(u8, "feed.xml") });

        const home_width = try std.unicode.utf8CountCodepoints(home);
        const rss_width = try std.unicode.utf8CountCodepoints(rss);
        const space_count = if (static_width > home_width + rss_width)
            static_width - home_width - rss_width
        else
            1;

        var first_line: std.ArrayList(u8) = .empty;
        defer first_line.deinit(self.allocator);
        try first_line.appendSlice(self.allocator, home);
        try first_line.appendNTimes(self.allocator, ' ', space_count);
        try first_line.appendSlice(self.allocator, rss);
        try self.addLine(first_line.items);
        try self.addLine("");

        var iter = std.mem.splitScalar(u8, header, '\n');
        while (iter.next()) |line| try self.addLine(line);
        try self.addLine("");
    }

    fn addHtml(self: *BlogPage, html: []const u8) !void {
        var parser = HtmlTextParser{ .page = self, .html = html, .index = 0 };
        try parser.parseNodes(false);
    }

    fn addWrappedText(self: *BlogPage, text: []const u8) !void {
        var rest = text;
        while (rest.len > 0) {
            const width = codepointCount(rest) catch rest.len;
            if (width <= max_line_len) {
                try self.addLine(rest);
                return;
            }

            var split_byte: usize = 0;
            var last_ws: usize = 0;
            var utf8 = (try std.unicode.Utf8View.init(rest)).iterator();
            var count: usize = 0;
            while (utf8.nextCodepointSlice()) |char| {
                if (count >= max_line_len) break;
                split_byte += char.len;
                if (isAsciiWhitespace(char)) last_ws = split_byte;
                count += 1;
            }

            const cut = if (last_ws > 0) last_ws else split_byte;
            try self.addLine(std.mem.trimEnd(u8, rest[0..cut], " \t\r\n"));
            rest = std.mem.trimStart(u8, rest[cut..], " \t\r\n");
        }
    }

    fn addCode(self: *BlogPage, text: []const u8) !void {
        var iter = std.mem.splitScalar(u8, text, '\n');
        while (iter.next()) |line| try self.addLine(std.mem.trimEnd(u8, line, " \t\r"));
    }

    fn addLine(self: *BlogPage, line: []const u8) !void {
        try self.lines.append(self.allocator, .{
            .content = try self.allocator.dupe(u8, line),
            .raw_html = false,
        });
    }

    fn addRawLine(self: *BlogPage, line: []const u8) !void {
        try self.lines.append(self.allocator, .{
            .content = try self.allocator.dupe(u8, line),
            .raw_html = true,
        });
    }

    fn addDragon(self: *BlogPage) !void {
        const html = try ansiToHtml(self.allocator, dragon_ansi);
        defer self.allocator.free(html);

        var iter = std.mem.splitScalar(u8, html, '\n');
        while (iter.next()) |line| try self.addRawLine(line);
        try self.addLine("");
    }

    fn toHtml(self: BlogPage, allocator: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var link_index: usize = 0;
        for (self.lines.items) |line| {
            if (line.raw_html) {
                try out.appendSlice(allocator, line.content);
            } else {
                try appendLinkedLineHtml(allocator, &out, line.content, self.links.items, &link_index);
            }
            try out.append(allocator, '\n');
        }

        return try out.toOwnedSlice(allocator);
    }
};

const HtmlTextParser = struct {
    page: *BlogPage,
    html: []const u8,
    index: usize,

    fn parseNodes(self: *HtmlTextParser, in_code: bool) !void {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.page.allocator);

        while (self.index < self.html.len) {
            if (self.html[self.index] != '<') {
                const end = std.mem.indexOfScalarPos(u8, self.html, self.index, '<') orelse self.html.len;
                try appendDecoded(self.page.allocator, &text, self.html[self.index..end]);
                self.index = end;
                continue;
            }

            if (std.mem.startsWith(u8, self.html[self.index..], "</")) {
                break;
            }

            const tag_end = std.mem.indexOfScalarPos(u8, self.html, self.index, '>') orelse return error.InvalidHtml;
            const tag = self.html[self.index + 1 .. tag_end];
            self.index = tag_end + 1;

            if (startsWithTag(tag, "p")) {
                try self.flushText(&text, in_code);
                try self.parseNodes(false);
                try self.consumeClose("p");
                try self.flushText(&text, false);
                try self.page.addLine("");
            } else if (startsWithTag(tag, "br")) {
                try self.flushText(&text, in_code);
            } else if (startsWithTag(tag, "a")) {
                const href = try dupAttr(self.page.allocator, tag, "href");
                errdefer self.page.allocator.free(href);
                try self.page.links.append(self.page.allocator, .{ .href = href });
                try text.append(self.page.allocator, '[');
                const link_end = std.mem.indexOf(u8, self.html[self.index..], "</a>") orelse return error.InvalidHtml;
                try appendHtmlText(self.page.allocator, &text, self.html[self.index .. self.index + link_end]);
                self.index += link_end;
                try self.consumeClose("a");
                try text.append(self.page.allocator, ']');
            } else if (startsWithTag(tag, "code")) {
                try self.flushText(&text, in_code);
                try self.parseNodes(true);
                try self.consumeClose("code");
                try self.flushText(&text, true);
            } else if (std.mem.indexOf(u8, tag, "data-node=\"dragon\"") != null) {
                try self.flushText(&text, in_code);
                try self.skipElement("div");
                try self.page.addDragon();
            } else {
                try self.parseNodes(in_code);
                const name = tagName(tag);
                if (name.len > 0) try self.consumeClose(name);
            }
        }

        try self.flushText(&text, in_code);
    }

    fn flushText(self: *HtmlTextParser, text: *std.ArrayList(u8), in_code: bool) !void {
        const trimmed = if (in_code) text.items else std.mem.trim(u8, text.items, " \t\r\n");
        if (trimmed.len > 0) {
            if (in_code) try self.page.addCode(trimmed) else try self.page.addWrappedText(trimmed);
        }
        text.clearRetainingCapacity();
    }

    fn consumeClose(self: *HtmlTextParser, name: []const u8) !void {
        const close_start = self.index;
        if (!std.mem.startsWith(u8, self.html[close_start..], "</")) return;
        const tag_end = std.mem.indexOfScalarPos(u8, self.html, close_start, '>') orelse return error.InvalidHtml;
        const close_tag = std.mem.trim(u8, self.html[close_start + 2 .. tag_end], " \t\r\n");
        if (std.mem.eql(u8, close_tag, name)) {
            self.index = tag_end + 1;
        }
    }

    fn skipElement(self: *HtmlTextParser, name: []const u8) !void {
        const close = try std.fmt.allocPrint(self.page.allocator, "</{s}>", .{name});
        defer self.page.allocator.free(close);
        const rel = std.mem.indexOf(u8, self.html[self.index..], close) orelse return error.InvalidHtml;
        self.index += rel + close.len;
    }
};

fn findBetween(haystack: []const u8, start: []const u8, end: []const u8) ?Match {
    const start_index = std.mem.indexOf(u8, haystack, start) orelse return null;
    const inner_start = start_index + start.len;
    const end_rel = std.mem.indexOf(u8, haystack[inner_start..], end) orelse return null;
    const end_index = inner_start + end_rel;
    return .{
        .inner = haystack[inner_start..end_index],
        .after = haystack[end_index + end.len ..],
    };
}

fn dupBetween(allocator: std.mem.Allocator, haystack: []const u8, start: []const u8, end: []const u8) ![]const u8 {
    const match = findBetween(haystack, start, end) orelse return error.MissingField;
    return allocator.dupe(u8, std.mem.trim(u8, match.inner, " \t\r\n"));
}

fn findTag(haystack: []const u8, name: []const u8) ?[]const u8 {
    const open = std.fmt.allocPrint(std.heap.page_allocator, "<{s}", .{name}) catch return null;
    defer std.heap.page_allocator.free(open);
    const start = std.mem.indexOf(u8, haystack, open) orelse return null;
    const end = std.mem.indexOfScalarPos(u8, haystack, start, '>') orelse return null;
    return haystack[start + 1 .. end];
}

fn dupAttr(allocator: std.mem.Allocator, tag: []const u8, name: []const u8) ![]const u8 {
    const key = try std.fmt.allocPrint(allocator, "{s}=\"", .{name});
    defer allocator.free(key);
    const start_rel = std.mem.indexOf(u8, tag, key) orelse return error.MissingAttribute;
    const value_start = start_rel + key.len;
    const value_end_rel = std.mem.indexOfScalarPos(u8, tag, value_start, '"') orelse return error.MissingAttribute;
    return try decodeEntitiesAlloc(allocator, tag[value_start..value_end_rel]);
}

fn startsWithTag(tag: []const u8, name: []const u8) bool {
    if (!std.mem.startsWith(u8, tag, name)) return false;
    return tag.len == name.len or std.ascii.isWhitespace(tag[name.len]) or tag[name.len] == '/' or tag[name.len] == '>';
}

fn tagName(tag: []const u8) []const u8 {
    var i: usize = 0;
    while (i < tag.len and !std.ascii.isWhitespace(tag[i]) and tag[i] != '/') : (i += 1) {}
    return tag[0..i];
}

fn replaceOnce(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    const index = std.mem.indexOf(u8, input, needle) orelse return error.MissingTemplateToken;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, input[0..index]);
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, input[index + needle.len ..]);
    return try out.toOwnedSlice(allocator);
}

fn pageTitle(allocator: std.mem.Allocator, page_name: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "XITLOG - ");
    for (page_name) |ch| try out.append(allocator, if (ch == '-') ' ' else ch);
    return try out.toOwnedSlice(allocator);
}

fn upperAsciiAlloc(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const out = try allocator.dupe(u8, input);
    for (out) |*ch| ch.* = std.ascii.toUpper(ch.*);
    return out;
}

fn formatDate(allocator: std.mem.Allocator, iso: []const u8) ![]const u8 {
    if (iso.len < 10) return allocator.dupe(u8, iso);
    const year = iso[0..4];
    const month_num = try std.fmt.parseInt(u8, iso[5..7], 10);
    const day_num = try std.fmt.parseInt(u8, iso[8..10], 10);
    const month = switch (month_num) {
        1 => "January",
        2 => "February",
        3 => "March",
        4 => "April",
        5 => "May",
        6 => "June",
        7 => "July",
        8 => "August",
        9 => "September",
        10 => "October",
        11 => "November",
        12 => "December",
        else => return error.InvalidDate,
    };
    return std.fmt.allocPrint(allocator, "{s} {}, {s}", .{ month, day_num, year });
}

fn codepointCount(bytes: []const u8) !usize {
    return std.unicode.utf8CountCodepoints(bytes);
}

fn isAsciiWhitespace(char: []const u8) bool {
    return char.len == 1 and std.ascii.isWhitespace(char[0]);
}

fn decodeEntitiesAlloc(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendDecoded(allocator, &out, input);
    return try out.toOwnedSlice(allocator);
}

fn appendHtmlText(allocator: std.mem.Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '<') {
            const end = std.mem.indexOfScalarPos(u8, input, i, '>') orelse return error.InvalidHtml;
            i = end + 1;
        } else {
            const end = std.mem.indexOfScalarPos(u8, input, i, '<') orelse input.len;
            try appendDecoded(allocator, out, input[i..end]);
            i = end;
        }
    }
}

fn appendLinkedLineHtml(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    line: []const u8,
    links: []const Link,
    link_index: *usize,
) !void {
    var in_link = false;
    var utf8 = (try std.unicode.Utf8View.init(line)).iterator();
    while (utf8.nextCodepointSlice()) |char| {
        if (!in_link and std.mem.eql(u8, char, "[") and link_index.* < links.len) {
            try out.appendSlice(allocator, "<a href='");
            try appendEscapedAttr(allocator, out, links[link_index.*].href);
            try out.appendSlice(allocator, "'>");
            in_link = true;
        } else if (in_link and std.mem.eql(u8, char, "]")) {
            try out.appendSlice(allocator, "</a>");
            link_index.* += 1;
            in_link = false;
        } else {
            try appendEscapedHtml(allocator, out, char);
        }
    }
    if (in_link) try out.appendSlice(allocator, "</a>");
}

const AnsiColor = enum(u8) {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
};

const AnsiStyle = struct {
    fg: ?AnsiColor = null,
    bg: ?AnsiColor = null,
    bright: bool = false,

    fn isDefault(self: AnsiStyle) bool {
        return self.fg == null and self.bg == null;
    }
};

fn ansiToHtml(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var style = AnsiStyle{};
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            const end = std.mem.indexOfScalarPos(u8, input, i + 2, 'm') orelse {
                i += 1;
                continue;
            };
            try applySgr(input[i + 2 .. end], &style);
            i = end + 1;
            continue;
        }

        if (input[i] == '\r') {
            i += 1;
            continue;
        }
        if (input[i] == '\n') {
            try out.append(allocator, '\n');
            i += 1;
            continue;
        }

        const len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
        const char = input[i..@min(i + len, input.len)];
        if (style.isDefault()) {
            try appendEscapedHtml(allocator, &out, char);
        } else {
            try appendAnsiSpan(allocator, &out, char, style);
        }
        i += char.len;
    }

    return try out.toOwnedSlice(allocator);
}

fn applySgr(params: []const u8, style: *AnsiStyle) !void {
    if (params.len == 0) {
        style.* = .{};
        return;
    }

    var iter = std.mem.splitScalar(u8, params, ';');
    while (iter.next()) |param| {
        const code = if (param.len == 0) 0 else try std.fmt.parseInt(u16, param, 10);
        switch (code) {
            0 => style.* = .{},
            1 => style.bright = true,
            22 => style.bright = false,
            30...37 => style.fg = @enumFromInt(code - 30),
            39 => style.fg = null,
            40...47 => style.bg = @enumFromInt(code - 40),
            49 => style.bg = null,
            90...97 => {
                style.fg = @enumFromInt(code - 90);
                style.bright = true;
            },
            100...107 => {
                style.bg = @enumFromInt(code - 100);
                style.bright = true;
            },
            else => {},
        }
    }
}

fn appendAnsiSpan(allocator: std.mem.Allocator, out: *std.ArrayList(u8), char: []const u8, style: AnsiStyle) !void {
    try out.appendSlice(allocator, "<span style='");
    if (style.fg) |fg| {
        const color = colorRgb(fg, style.bright);
        const style_text = try std.fmt.allocPrint(allocator, "color: rgba({}, {}, {}, 1.0);", .{ color[0], color[1], color[2] });
        defer allocator.free(style_text);
        try out.appendSlice(allocator, style_text);
    }
    if (style.bg) |bg| {
        const color = colorRgb(bg, style.bright);
        const style_text = try std.fmt.allocPrint(allocator, "background-color: rgba({}, {}, {}, 1.0);", .{ color[0], color[1], color[2] });
        defer allocator.free(style_text);
        try out.appendSlice(allocator, style_text);
    }
    try out.appendSlice(allocator, "'>");
    try appendEscapedHtml(allocator, out, char);
    try out.appendSlice(allocator, "</span>");
}

fn colorRgb(color: AnsiColor, bright: bool) [3]u8 {
    if (bright) {
        return switch (color) {
            .black => .{ 0, 0, 0 },
            .red => .{ 238, 119, 109 },
            .green => .{ 141, 245, 123 },
            .yellow => .{ 255, 250, 127 },
            .blue => .{ 103, 118, 246 },
            .magenta => .{ 238, 131, 248 },
            .cyan => .{ 141, 250, 253 },
            .white => .{ 255, 255, 255 },
        };
    }

    return switch (color) {
        .black => .{ 0, 0, 0 },
        .red => .{ 255, 0, 0 },
        .green => .{ 0, 128, 0 },
        .yellow => .{ 255, 255, 0 },
        .blue => .{ 0, 0, 255 },
        .magenta => .{ 255, 0, 255 },
        .cyan => .{ 0, 255, 255 },
        .white => .{ 255, 255, 255 },
    };
}

fn appendDecoded(allocator: std.mem.Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '&') {
            if (std.mem.startsWith(u8, input[i..], "&amp;")) {
                try out.append(allocator, '&');
                i += 5;
            } else if (std.mem.startsWith(u8, input[i..], "&lt;")) {
                try out.append(allocator, '<');
                i += 4;
            } else if (std.mem.startsWith(u8, input[i..], "&gt;")) {
                try out.append(allocator, '>');
                i += 4;
            } else if (std.mem.startsWith(u8, input[i..], "&quot;")) {
                try out.append(allocator, '"');
                i += 6;
            } else if (std.mem.startsWith(u8, input[i..], "&#39;")) {
                try out.append(allocator, '\'');
                i += 5;
            } else if (std.mem.startsWith(u8, input[i..], "&nbsp;")) {
                try out.append(allocator, ' ');
                i += 6;
            } else {
                try out.append(allocator, input[i]);
                i += 1;
            }
        } else {
            try out.append(allocator, input[i]);
            i += 1;
        }
    }
}

fn appendEscapedHtml(allocator: std.mem.Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    for (input) |ch| {
        switch (ch) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            else => try out.append(allocator, ch),
        }
    }
}

fn appendEscapedAttr(allocator: std.mem.Allocator, out: *std.ArrayList(u8), input: []const u8) !void {
    for (input) |ch| {
        switch (ch) {
            '&' => try out.appendSlice(allocator, "&amp;"),
            '\'' => try out.appendSlice(allocator, "&#39;"),
            '<' => try out.appendSlice(allocator, "&lt;"),
            '>' => try out.appendSlice(allocator, "&gt;"),
            else => try out.append(allocator, ch),
        }
    }
}
