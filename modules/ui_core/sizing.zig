//! Contextual CSS length arithmetic. Missing host metrics remain unresolved.
const std = @import("std");

pub const Context = struct {
    percentage: ?f32 = null,
    font_size: ?f32 = null,
    root_font_size: ?f32 = null,
    x_height: ?f32 = null,
    cap_height: ?f32 = null,
    zero_advance: ?f32 = null,
    ideographic_advance: ?f32 = null,
    root_x_height: ?f32 = null,
    root_cap_height: ?f32 = null,
    root_zero_advance: ?f32 = null,
    root_ideographic_advance: ?f32 = null,
    line_height: ?f32 = null,
    root_line_height: ?f32 = null,
    viewport_width: ?f32 = null,
    viewport_height: ?f32 = null,
    small_viewport_width: ?f32 = null,
    small_viewport_height: ?f32 = null,
    large_viewport_width: ?f32 = null,
    large_viewport_height: ?f32 = null,
    dynamic_viewport_width: ?f32 = null,
    dynamic_viewport_height: ?f32 = null,
    viewport_inline: ?f32 = null,
    viewport_block: ?f32 = null,
    small_viewport_inline: ?f32 = null,
    small_viewport_block: ?f32 = null,
    large_viewport_inline: ?f32 = null,
    large_viewport_block: ?f32 = null,
    dynamic_viewport_inline: ?f32 = null,
    dynamic_viewport_block: ?f32 = null,
    container_width: ?f32 = null,
    container_height: ?f32 = null,
    container_inline: ?f32 = null,
    container_block: ?f32 = null,
};

pub const AvailableSpace = union(enum) { definite: f32, min_content, max_content };
pub const Keyword = enum { auto, none, min_content, max_content, fit_content };
pub const Resolution = union(enum) { length: f32, keyword: Keyword, unresolved };
const Dimension = enum { number, length };
const Quantity = struct { value: ?f32, dimension: Dimension };

fn scaled(value: f32, basis: ?f32, factor: f32) ?f32 {
    return if (basis) |b| value * b * factor else null;
}

fn extremum(a: ?f32, b: ?f32, minimum: bool) ?f32 {
    if (a == null or b == null) return null;
    return if (minimum) @min(a.?, b.?) else @max(a.?, b.?);
}

pub fn resolve(input: []const u8, context: Context) !Resolution {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    const keywords = .{ .{ "auto", Keyword.auto }, .{ "none", Keyword.none }, .{ "min-content", Keyword.min_content }, .{ "max-content", Keyword.max_content }, .{ "fit-content", Keyword.fit_content } };
    inline for (keywords) |pair| if (std.mem.eql(u8, trimmed, pair[0])) return .{ .keyword = pair[1] };
    var parser = Parser{ .input = trimmed, .context = context };
    const result = try parser.expression();
    parser.whitespace();
    if (parser.pos != trimmed.len) return error.InvalidLength;
    if (result.dimension == .number and result.value != null and result.value.? != 0) return error.InvalidLength;
    const value = result.value orelse return .unresolved;
    if (!std.math.isFinite(value)) return error.InvalidLength;
    return .{ .length = value };
}

const Parser = struct {
    input: []const u8,
    pos: usize = 0,
    context: Context,

    fn whitespace(p: *Parser) void {
        while (p.pos < p.input.len and std.ascii.isWhitespace(p.input[p.pos])) : (p.pos += 1) {}
    }
    fn take(p: *Parser, byte: u8) bool {
        p.whitespace();
        if (p.pos < p.input.len and p.input[p.pos] == byte) {
            p.pos += 1;
            return true;
        }
        return false;
    }
    fn expression(p: *Parser) anyerror!Quantity {
        var lhs = try p.product();
        while (true) {
            const add = if (p.take('+')) true else if (p.take('-')) false else break;
            const rhs = try p.product();
            if (lhs.dimension != rhs.dimension) return error.IncompatibleDimensions;
            lhs.value = if (lhs.value != null and rhs.value != null) (if (add) lhs.value.? + rhs.value.? else lhs.value.? - rhs.value.?) else null;
        }
        return lhs;
    }
    fn product(p: *Parser) anyerror!Quantity {
        var lhs = try p.atom();
        while (true) {
            const multiply = if (p.take('*')) true else if (p.take('/')) false else break;
            const rhs = try p.atom();
            if (multiply) {
                if (lhs.dimension == .length and rhs.dimension == .length) return error.IncompatibleDimensions;
                if (rhs.dimension == .length) lhs.dimension = .length;
            } else {
                if (rhs.dimension != .number) return error.IncompatibleDimensions;
                if (rhs.value != null and rhs.value.? == 0) return error.InvalidLength;
            }
            lhs.value = if (lhs.value != null and rhs.value != null) (if (multiply) lhs.value.? * rhs.value.? else lhs.value.? / rhs.value.?) else null;
        }
        return lhs;
    }
    fn atom(p: *Parser) anyerror!Quantity {
        p.whitespace();
        if (p.take('(')) {
            const value = try p.expression();
            if (!p.take(')')) return error.InvalidLength;
            return value;
        }
        const start = p.pos;
        if (p.pos < p.input.len and (p.input[p.pos] == '+' or p.input[p.pos] == '-')) p.pos += 1;
        while (p.pos < p.input.len and (std.ascii.isDigit(p.input[p.pos]) or p.input[p.pos] == '.')) : (p.pos += 1) {}
        if (p.pos > start and !(p.pos == start + 1 and (p.input[start] == '+' or p.input[start] == '-'))) {
            const value = std.fmt.parseFloat(f32, p.input[start..p.pos]) catch return error.InvalidLength;
            if (!std.math.isFinite(value)) return error.InvalidLength;
            const unit_start = p.pos;
            while (p.pos < p.input.len and (std.ascii.isAlphabetic(p.input[p.pos]) or p.input[p.pos] == '%')) : (p.pos += 1) {}
            const unit = p.input[unit_start..p.pos];
            if (unit.len == 0) return .{ .value = value, .dimension = .number };
            return .{ .value = try p.unit(value, unit), .dimension = .length };
        }
        p.pos = start;
        while (p.pos < p.input.len and (std.ascii.isAlphabetic(p.input[p.pos]) or p.input[p.pos] == '-')) : (p.pos += 1) {}
        const name = p.input[start..p.pos];
        if (!p.take('(')) return error.InvalidLength;
        if (std.mem.eql(u8, name, "calc")) {
            const q = try p.expression();
            if (!p.take(')')) return error.InvalidLength;
            return q;
        }
        const is_min = std.mem.eql(u8, name, "min");
        const is_max = std.mem.eql(u8, name, "max");
        const is_clamp = std.mem.eql(u8, name, "clamp");
        if (!is_min and !is_max and !is_clamp) return error.InvalidLength;
        var first = try p.expression();
        if (!p.take(',')) return error.InvalidLength;
        const second = try p.expression();
        if (first.dimension != second.dimension) return error.IncompatibleDimensions;
        if (is_clamp) {
            if (!p.take(',')) return error.InvalidLength;
            const third = try p.expression();
            if (third.dimension != first.dimension or !p.take(')')) return error.InvalidLength;
            first.value = extremum(first.value, extremum(second.value, third.value, true), false);
        } else {
            first.value = extremum(first.value, second.value, is_min);
            while (p.take(',')) {
                const next = try p.expression();
                if (next.dimension != first.dimension) return error.IncompatibleDimensions;
                first.value = extremum(first.value, next.value, is_min);
            }
            if (!p.take(')')) return error.InvalidLength;
        }
        return first;
    }
    fn unit(p: *Parser, value: f32, u: []const u8) !?f32 {
        const c = p.context;
        const fixed = .{ .{ "px", 1.0 }, .{ "in", 96.0 }, .{ "cm", 96.0 / 2.54 }, .{ "mm", 96.0 / 25.4 }, .{ "q", 96.0 / 101.6 }, .{ "pt", 96.0 / 72.0 }, .{ "pc", 16.0 } };
        inline for (fixed) |pair| if (std.mem.eql(u8, u, pair[0])) return value * pair[1];
        const relatives = .{
            .{ "%", c.percentage, 0.01 },                                                             .{ "em", c.font_size, 1.0 },                                                          .{ "rem", c.root_font_size, 1.0 },
            .{ "ex", c.x_height, 1.0 },                                                               .{ "cap", c.cap_height, 1.0 },                                                        .{ "ch", c.zero_advance, 1.0 },
            .{ "ic", c.ideographic_advance, 1.0 },                                                    .{ "lh", c.line_height, 1.0 },                                                        .{ "rlh", c.root_line_height, 1.0 },
            .{ "vw", c.viewport_width, 0.01 },                                                        .{ "vh", c.viewport_height, 0.01 },                                                   .{ "vmin", extremum(c.viewport_width, c.viewport_height, true), 0.01 },
            .{ "vmax", extremum(c.viewport_width, c.viewport_height, false), 0.01 },                  .{ "svw", c.small_viewport_width, 0.01 },                                             .{ "svh", c.small_viewport_height, 0.01 },
            .{ "svmin", extremum(c.small_viewport_width, c.small_viewport_height, true), 0.01 },      .{ "svmax", extremum(c.small_viewport_width, c.small_viewport_height, false), 0.01 }, .{ "lvw", c.large_viewport_width, 0.01 },
            .{ "lvh", c.large_viewport_height, 0.01 },                                                .{ "lvmin", extremum(c.large_viewport_width, c.large_viewport_height, true), 0.01 },  .{ "lvmax", extremum(c.large_viewport_width, c.large_viewport_height, false), 0.01 },
            .{ "dvw", c.dynamic_viewport_width, 0.01 },                                               .{ "dvh", c.dynamic_viewport_height, 0.01 },                                          .{ "dvmin", extremum(c.dynamic_viewport_width, c.dynamic_viewport_height, true), 0.01 },
            .{ "dvmax", extremum(c.dynamic_viewport_width, c.dynamic_viewport_height, false), 0.01 }, .{ "cqw", c.container_width, 0.01 },                                                  .{ "cqh", c.container_height, 0.01 },
            .{ "cqi", c.container_inline, 0.01 },                                                     .{ "cqb", c.container_block, 0.01 },                                                  .{ "cqmin", extremum(c.container_inline, c.container_block, true), 0.01 },
            .{ "cqmax", extremum(c.container_inline, c.container_block, false), 0.01 },               .{ "rex", c.root_x_height, 1.0 },                                                     .{ "rcap", c.root_cap_height, 1.0 },
            .{ "rch", c.root_zero_advance, 1.0 },                                                     .{ "ric", c.root_ideographic_advance, 1.0 },                                          .{ "vi", c.viewport_inline, 0.01 },
            .{ "vb", c.viewport_block, 0.01 },                                                        .{ "svi", c.small_viewport_inline, 0.01 },                                            .{ "svb", c.small_viewport_block, 0.01 },
            .{ "lvi", c.large_viewport_inline, 0.01 },                                                .{ "lvb", c.large_viewport_block, 0.01 },                                             .{ "dvi", c.dynamic_viewport_inline, 0.01 },
            .{ "dvb", c.dynamic_viewport_block, 0.01 },
        };
        inline for (relatives) |pair| if (std.mem.eql(u8, u, pair[0])) return scaled(value, pair[1], pair[2]);
        return error.UnsupportedUnit;
    }
};
