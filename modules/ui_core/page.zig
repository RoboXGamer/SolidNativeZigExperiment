//! CSS Paged Media Module Level 3 & Fragmentation Module Level 3 implementation.
//! Covers:
//! - @page rule setup, named pages (page property)
//! - size descriptor: standard paper sizes (A3, A4, A5, B4, B5, JIS-B4, JIS-B5, letter, legal, ledger),
//!   orientation (portrait, landscape), explicit lengths
//! - Page selectors (:first, :left, :right, :blank, named pages)
//! - Page breaks (break-before, break-after, break-inside) in paged contexts
const std = @import("std");
const geometry = @import("geometry.zig");
const Rect = geometry.Rect;
const Edges = geometry.Edges;

pub const PageOrientation = enum {
    portrait,
    landscape,
};

pub const PageDimensions = struct {
    width: f32,
    height: f32,

    pub fn orient(self: PageDimensions, orientation: PageOrientation) PageDimensions {
        const min_dim = @min(self.width, self.height);
        const max_dim = @max(self.width, self.height);
        return switch (orientation) {
            .portrait => .{ .width = min_dim, .height = max_dim },
            .landscape => .{ .width = max_dim, .height = min_dim },
        };
    }
};

// 1 mm in PostScript points = 72 / 25.4 ~= 2.83464567 pt
const MM_TO_PT: f32 = 72.0 / 25.4;
const IN_TO_PT: f32 = 72.0;

pub const standard_sizes = struct {
    // JIS sizes (Japanese Industrial Standards B4 & B5)
    pub const jis_b4 = PageDimensions{ .width = 257.0 * MM_TO_PT, .height = 364.0 * MM_TO_PT };
    pub const jis_b5 = PageDimensions{ .width = 182.0 * MM_TO_PT, .height = 257.0 * MM_TO_PT };

    // ISO sizes
    pub const a3 = PageDimensions{ .width = 297.0 * MM_TO_PT, .height = 420.0 * MM_TO_PT };
    pub const a4 = PageDimensions{ .width = 210.0 * MM_TO_PT, .height = 297.0 * MM_TO_PT };
    pub const a5 = PageDimensions{ .width = 148.0 * MM_TO_PT, .height = 210.0 * MM_TO_PT };
    pub const b4 = PageDimensions{ .width = 250.0 * MM_TO_PT, .height = 353.0 * MM_TO_PT };
    pub const b5 = PageDimensions{ .width = 176.0 * MM_TO_PT, .height = 250.0 * MM_TO_PT };

    // North American sizes
    pub const letter = PageDimensions{ .width = 8.5 * IN_TO_PT, .height = 11.0 * IN_TO_PT };
    pub const legal = PageDimensions{ .width = 8.5 * IN_TO_PT, .height = 14.0 * IN_TO_PT };
    pub const ledger = PageDimensions{ .width = 11.0 * IN_TO_PT, .height = 17.0 * IN_TO_PT };
};

/// Parse page size keyword or dimensions from CSS `@page { size: ... }`.
pub fn parsePageSize(raw: []const u8) ?PageDimensions {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return null;

    var orientation: ?PageOrientation = null;
    var base_dim: ?PageDimensions = null;

    var it = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
    var token_count: usize = 0;
    var lengths: [2]f32 = [_]f32{0} ** 2;
    var length_count: usize = 0;

    while (it.next()) |token| : (token_count += 1) {
        if (std.ascii.eqlIgnoreCase(token, "portrait")) {
            orientation = .portrait;
        } else if (std.ascii.eqlIgnoreCase(token, "landscape")) {
            orientation = .landscape;
        } else if (std.ascii.eqlIgnoreCase(token, "jis-b4") or std.ascii.eqlIgnoreCase(token, "jis_b4")) {
            base_dim = standard_sizes.jis_b4;
        } else if (std.ascii.eqlIgnoreCase(token, "jis-b5") or std.ascii.eqlIgnoreCase(token, "jis_b5")) {
            base_dim = standard_sizes.jis_b5;
        } else if (std.ascii.eqlIgnoreCase(token, "a4")) {
            base_dim = standard_sizes.a4;
        } else if (std.ascii.eqlIgnoreCase(token, "a3")) {
            base_dim = standard_sizes.a3;
        } else if (std.ascii.eqlIgnoreCase(token, "a5")) {
            base_dim = standard_sizes.a5;
        } else if (std.ascii.eqlIgnoreCase(token, "b4")) {
            base_dim = standard_sizes.b4;
        } else if (std.ascii.eqlIgnoreCase(token, "b5")) {
            base_dim = standard_sizes.b5;
        } else if (std.ascii.eqlIgnoreCase(token, "letter")) {
            base_dim = standard_sizes.letter;
        } else if (std.ascii.eqlIgnoreCase(token, "legal")) {
            base_dim = standard_sizes.legal;
        } else if (std.ascii.eqlIgnoreCase(token, "ledger")) {
            base_dim = standard_sizes.ledger;
        } else if (std.ascii.eqlIgnoreCase(token, "auto")) {
            base_dim = standard_sizes.a4;
        } else {
            // Attempt length parsing (px, pt, in, mm, cm)
            if (parseLength(token)) |val| {
                if (length_count < 2) {
                    lengths[length_count] = val;
                    length_count += 1;
                }
            }
        }
    }

    if (length_count == 1) {
        base_dim = PageDimensions{ .width = lengths[0], .height = lengths[0] };
    } else if (length_count == 2) {
        base_dim = PageDimensions{ .width = lengths[0], .height = lengths[1] };
    }

    const final_dim = base_dim orelse standard_sizes.a4;
    return if (orientation) |o| final_dim.orient(o) else final_dim;
}

fn parseLength(str: []const u8) ?f32 {
    const s = std.mem.trim(u8, str, " \t\r\n");
    if (s.len == 0) return null;
    var num_len: usize = 0;
    while (num_len < s.len and (std.ascii.isDigit(s[num_len]) or s[num_len] == '.' or s[num_len] == '-' or s[num_len] == '+')) : (num_len += 1) {}
    if (num_len == 0) return null;
    const num = std.fmt.parseFloat(f32, s[0..num_len]) catch return null;
    const unit = s[num_len..];
    if (std.ascii.eqlIgnoreCase(unit, "in")) return num * IN_TO_PT;
    if (std.ascii.eqlIgnoreCase(unit, "mm")) return num * MM_TO_PT;
    if (std.ascii.eqlIgnoreCase(unit, "cm")) return num * 10.0 * MM_TO_PT;
    if (std.ascii.eqlIgnoreCase(unit, "pt") or unit.len == 0) return num;
    if (std.ascii.eqlIgnoreCase(unit, "px")) return num * 0.75; // 96px = 72pt
    return num;
}

pub const PageSelectorKind = enum {
    all,
    first,
    left,
    right,
    blank,
};

pub const PageSelector = struct {
    name: ?[]const u8 = null,
    kind: PageSelectorKind = .all,

    pub fn parse(raw: []const u8) PageSelector {
        var s = std.mem.trim(u8, raw, " \t\r\n");
        if (s.len == 0) return .{ .kind = .all };

        var name: ?[]const u8 = null;
        var kind: PageSelectorKind = .all;

        if (std.mem.indexOfScalar(u8, s, ':')) |colon| {
            if (colon > 0) name = s[0..colon];
            const pseudo = s[colon + 1 ..];
            if (std.ascii.eqlIgnoreCase(pseudo, "first")) kind = .first;
            if (std.ascii.eqlIgnoreCase(pseudo, "left")) kind = .left;
            if (std.ascii.eqlIgnoreCase(pseudo, "right")) kind = .right;
            if (std.ascii.eqlIgnoreCase(pseudo, "blank")) kind = .blank;
        } else if (s[0] == ':') {
            const pseudo = s[1..];
            if (std.ascii.eqlIgnoreCase(pseudo, "first")) kind = .first;
            if (std.ascii.eqlIgnoreCase(pseudo, "left")) kind = .left;
            if (std.ascii.eqlIgnoreCase(pseudo, "right")) kind = .right;
            if (std.ascii.eqlIgnoreCase(pseudo, "blank")) kind = .blank;
        } else {
            name = s;
        }

        return .{ .name = name, .kind = kind };
    }

    pub fn matches(self: PageSelector, page_index: usize, is_left: bool, is_blank: bool, current_name: ?[]const u8) bool {
        if (self.name) |n| {
            if (current_name) |cn| {
                if (!std.ascii.eqlIgnoreCase(n, cn)) return false;
            } else {
                return false;
            }
        }
        return switch (self.kind) {
            .all => true,
            .first => page_index == 0,
            .left => is_left,
            .right => !is_left,
            .blank => is_blank,
        };
    }
};

pub const BreakValue = enum {
    auto,
    avoid,
    avoid_page,
    page,
    left,
    right,
    recto,
    verso,
    column,
    avoid_column,

    pub fn fromString(str: []const u8) BreakValue {
        const s = std.mem.trim(u8, str, " \t\r\n");
        if (std.ascii.eqlIgnoreCase(s, "avoid")) return .avoid;
        if (std.ascii.eqlIgnoreCase(s, "avoid-page")) return .avoid_page;
        if (std.ascii.eqlIgnoreCase(s, "page")) return .page;
        if (std.ascii.eqlIgnoreCase(s, "left")) return .left;
        if (std.ascii.eqlIgnoreCase(s, "right")) return .right;
        if (std.ascii.eqlIgnoreCase(s, "recto")) return .recto;
        if (std.ascii.eqlIgnoreCase(s, "verso")) return .verso;
        if (std.ascii.eqlIgnoreCase(s, "column")) return .column;
        if (std.ascii.eqlIgnoreCase(s, "avoid-column")) return .avoid_column;
        return .auto;
    }

    pub fn isForcedPageBreak(self: BreakValue) bool {
        return self == .page or self == .left or self == .right or self == .recto or self == .verso;
    }

    pub fn isAvoidPageBreak(self: BreakValue) bool {
        return self == .avoid or self == .avoid_page;
    }
};

pub const PageSetup = struct {
    name: []const u8 = "auto",
    size: PageDimensions = standard_sizes.a4,
    margin: Edges = .{ .top = 36, .right = 36, .bottom = 36, .left = 36 }, // 0.5in margins
};

pub const PageBox = struct {
    page_number: usize,
    dimensions: PageDimensions,
    margin: Edges,
    content_rect: Rect,
    is_left: bool,
    is_blank: bool = false,
};

/// Paginate content items based on page capacity and page break properties.
pub const Paginator = struct {
    setup: PageSetup,

    pub fn init(setup: PageSetup) Paginator {
        return .{ .setup = setup };
    }

    pub fn paginate(self: Paginator, allocator: std.mem.Allocator, item_count: usize, heights: []const f32, breaks_before: []const BreakValue, breaks_after: []const BreakValue, breaks_inside: []const BreakValue) ![]PageBox {
        var pages: std.ArrayList(PageBox) = .empty;
        errdefer pages.deinit(allocator);

        var current_page_idx: usize = 0;
        var is_left: bool = false; // Page 1 is right/recto by convention in duplex printing

        var content_h = self.setup.size.height - self.setup.margin.vertical();
        var remaining_h = content_h;

        // Start first page
        try pages.append(allocator, .{
            .page_number = current_page_idx + 1,
            .dimensions = self.setup.size,
            .margin = self.setup.margin,
            .content_rect = .{
                .x = self.setup.margin.left,
                .y = self.setup.margin.top,
                .width = self.setup.size.width - self.setup.margin.horizontal(),
                .height = content_h,
            },
            .is_left = is_left,
            .is_blank = false,
        });

        for (0..item_count) |i| {
            const h = if (i < heights.len) heights[i] else 0;
            const bb = if (i < breaks_before.len) breaks_before[i] else .auto;
            const ba = if (i < breaks_after.len) breaks_after[i] else .auto;
            const bi = if (i < breaks_inside.len) breaks_inside[i] else .auto;

            // Check forced break-before
            if (bb.isForcedPageBreak()) {
                current_page_idx += 1;
                is_left = !is_left;
                // If break-before is 'left' and we landed on right page, insert a blank page
                if (bb == .left and !is_left) {
                    try pages.append(allocator, .{
                        .page_number = current_page_idx + 1,
                        .dimensions = self.setup.size,
                        .margin = self.setup.margin,
                        .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                        .is_left = false,
                        .is_blank = true,
                    });
                    current_page_idx += 1;
                    is_left = true;
                } else if (bb == .right and is_left) {
                    try pages.append(allocator, .{
                        .page_number = current_page_idx + 1,
                        .dimensions = self.setup.size,
                        .margin = self.setup.margin,
                        .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                        .is_left = true,
                        .is_blank = true,
                    });
                    current_page_idx += 1;
                    is_left = false;
                }

                try pages.append(allocator, .{
                    .page_number = current_page_idx + 1,
                    .dimensions = self.setup.size,
                    .margin = self.setup.margin,
                    .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                    .is_left = is_left,
                    .is_blank = false,
                });
                remaining_h = content_h;
            }

            // Check if item fits on current page
            if (h > remaining_h and (bi.isAvoidPageBreak() or remaining_h < content_h * 0.2)) {
                // Move item to next page
                current_page_idx += 1;
                is_left = !is_left;
                try pages.append(allocator, .{
                    .page_number = current_page_idx + 1,
                    .dimensions = self.setup.size,
                    .margin = self.setup.margin,
                    .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                    .is_left = is_left,
                    .is_blank = false,
                });
                remaining_h = content_h;
            }

            remaining_h = if (remaining_h > h) remaining_h - h else 0;

            // Check forced break-after
            if (ba.isForcedPageBreak()) {
                current_page_idx += 1;
                is_left = !is_left;
                if (ba == .left and !is_left) {
                    try pages.append(allocator, .{
                        .page_number = current_page_idx + 1,
                        .dimensions = self.setup.size,
                        .margin = self.setup.margin,
                        .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                        .is_left = false,
                        .is_blank = true,
                    });
                    current_page_idx += 1;
                    is_left = true;
                } else if (ba == .right and is_left) {
                    try pages.append(allocator, .{
                        .page_number = current_page_idx + 1,
                        .dimensions = self.setup.size,
                        .margin = self.setup.margin,
                        .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                        .is_left = true,
                        .is_blank = true,
                    });
                    current_page_idx += 1;
                    is_left = false;
                }

                try pages.append(allocator, .{
                    .page_number = current_page_idx + 1,
                    .dimensions = self.setup.size,
                    .margin = self.setup.margin,
                    .content_rect = .{ .x = self.setup.margin.left, .y = self.setup.margin.top, .width = self.setup.size.width - self.setup.margin.horizontal(), .height = content_h },
                    .is_left = is_left,
                    .is_blank = false,
                });
                remaining_h = content_h;
            }
        }

        return pages.toOwnedSlice(allocator);
    }
};
