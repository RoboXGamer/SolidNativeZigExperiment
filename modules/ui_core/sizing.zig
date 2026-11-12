//! Contextual CSS length arithmetic. Missing host metrics remain unresolved.
const std = @import("std");
const math = @import("css_math.zig");

pub const Context = struct {
    percentage: ?f32 = null,
    percentage_is_number: bool = false,
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
pub const Dimension = enum { number, length, angle, time, frequency, resolution, flex };
pub const Quantity = struct { value: ?f32, dimension: Dimension };

fn scaled(value: f32, basis: ?f32, factor: f32) ?f32 {
    return if (basis) |b| value * b * factor else null;
}

fn extremum(a: ?f32, b: ?f32, minimum: bool) ?f32 {
    if (a == null or b == null) return null;
    return math.extremum(a.?, b.?, minimum);
}

/// Typed math entry point. Canonical units: px, degrees, seconds, Hz, dppx, fr.
pub fn resolveValue(input: []const u8, context: Context) !Quantity {
    var parser = Parser{ .input = std.mem.trim(u8, input, " \t\r\n"), .context = context };
    const result = try parser.expression();
    parser.whitespace();
    if (parser.pos != parser.input.len) return error.InvalidLength;
    return result;
}
pub fn resolveNumber(input: []const u8, context: Context) !?f32 {
    var ctx = context;
    ctx.percentage_is_number = true;
    ctx.percentage = ctx.percentage orelse 1;
    const result = try resolveValue(input, ctx);
    if (result.dimension != .number) return error.IncompatibleDimensions;
    return result.value;
}

pub fn resolve(input: []const u8, context: Context) !Resolution {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    const keywords = .{ .{ "auto", Keyword.auto }, .{ "none", Keyword.none }, .{ "min-content", Keyword.min_content }, .{ "max-content", Keyword.max_content }, .{ "fit-content", Keyword.fit_content } };
    inline for (keywords) |pair| if (std.mem.eql(u8, trimmed, pair[0])) return .{ .keyword = pair[1] };
    var parser = Parser{ .input = trimmed, .context = context };
    const result = try parser.expression();
    parser.whitespace();
    if (parser.pos != trimmed.len) return error.InvalidLength;
    if (result.dimension != .length and !(result.dimension == .number and result.value != null and result.value.? == 0)) return error.InvalidLength;
    const value = result.value orelse return .unresolved;
    if (!std.math.isFinite(value)) return error.InvalidLength;
    return .{ .length = if (value == 0) 0 else value };
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
                if (lhs.dimension != .number and rhs.dimension != .number) return error.IncompatibleDimensions;
                if (rhs.dimension != .number) lhs.dimension = rhs.dimension;
            } else {
                if (rhs.dimension != .number) {
                    if (lhs.dimension != rhs.dimension) return error.IncompatibleDimensions;
                    lhs.dimension = .number;
                }
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
            if (p.pos < p.input.len and (p.input[p.pos] == 'e' or p.input[p.pos] == 'E')) {
                var exponent_end = p.pos + 1;
                if (exponent_end < p.input.len and (p.input[exponent_end] == '+' or p.input[exponent_end] == '-')) exponent_end += 1;
                const digits_start = exponent_end;
                while (exponent_end < p.input.len and std.ascii.isDigit(p.input[exponent_end])) : (exponent_end += 1) {}
                if (exponent_end > digits_start) p.pos = exponent_end;
            }
            const parsed = std.fmt.parseFloat(f32, p.input[start..p.pos]) catch return error.InvalidLength;
            // A signed numeric token still denotes unsigned CSS zero. Negative
            // zero produced by calculations is retained until the used value.
            const value: f32 = if (parsed == 0) 0 else parsed;
            if (!std.math.isFinite(value)) return error.InvalidLength;
            const unit_start = p.pos;
            while (p.pos < p.input.len and (std.ascii.isAlphabetic(p.input[p.pos]) or p.input[p.pos] == '%')) : (p.pos += 1) {}
            const unit_str = p.input[unit_start..p.pos];
            if (unit_str.len == 0) return .{ .value = value, .dimension = .number };
            const typed = .{ .{ "deg", Dimension.angle, @as(f32, 1) }, .{ "rad", Dimension.angle, @as(f32, 180 / std.math.pi) }, .{ "grad", Dimension.angle, @as(f32, 0.9) }, .{ "turn", Dimension.angle, @as(f32, 360) }, .{ "s", Dimension.time, @as(f32, 1) }, .{ "ms", Dimension.time, @as(f32, 0.001) }, .{ "Hz", Dimension.frequency, @as(f32, 1) }, .{ "kHz", Dimension.frequency, @as(f32, 1000) }, .{ "dppx", Dimension.resolution, @as(f32, 1) }, .{ "dpi", Dimension.resolution, @as(f32, 1.0 / 96) }, .{ "dpcm", Dimension.resolution, @as(f32, 2.54 / 96) }, .{ "fr", Dimension.flex, @as(f32, 1) } };
            inline for (typed) |t| if (std.ascii.eqlIgnoreCase(unit_str, t[0])) return .{ .value = value * t[2], .dimension = t[1] };
            return .{ .value = try p.unit(value, unit_str), .dimension = if (p.context.percentage_is_number and std.mem.eql(u8, unit_str, "%")) .number else .length };
        }
        p.pos = start;
        while (p.pos < p.input.len and (std.ascii.isAlphanumeric(p.input[p.pos]) or p.input[p.pos] == '-')) : (p.pos += 1) {}
        const name = p.input[start..p.pos];
        if (std.ascii.eqlIgnoreCase(name, "pi")) return .{ .dimension = .number, .value = std.math.pi };
        if (std.ascii.eqlIgnoreCase(name, "e")) return .{ .dimension = .number, .value = std.math.e };
        if (std.ascii.eqlIgnoreCase(name, "infinity")) return .{ .dimension = .number, .value = std.math.inf(f32) };
        if (std.ascii.eqlIgnoreCase(name, "-infinity")) return .{ .dimension = .number, .value = -std.math.inf(f32) };
        if (std.ascii.eqlIgnoreCase(name, "NaN")) return .{ .dimension = .number, .value = std.math.nan(f32) };
        if (!p.take('(')) return error.InvalidLength;
        if (try p.mathFunction(name)) |q| return q;
        if (std.ascii.eqlIgnoreCase(name, "abs") or std.ascii.eqlIgnoreCase(name, "sign")) {
            var q = try p.expression();
            if (!p.take(')')) return error.InvalidLength;
            if (std.ascii.eqlIgnoreCase(name, "abs")) {
                if (q.value) |v| q.value = @abs(v);
            } else {
                q.dimension = .number;
                if (q.value) |v| q.value = if (std.math.isNan(v) or v == 0) v else if (v < 0) @as(f32, -1) else 1;
            }
            return q;
        }
        if (std.ascii.eqlIgnoreCase(name, "calc")) {
            const q = try p.expression();
            if (!p.take(')')) return error.InvalidLength;
            return q;
        }
        const is_min = std.ascii.eqlIgnoreCase(name, "min");
        const is_max = std.ascii.eqlIgnoreCase(name, "max");
        const is_clamp = std.ascii.eqlIgnoreCase(name, "clamp");
        if (!is_min and !is_max and !is_clamp) return error.InvalidLength;
        var first = try p.expression();
        if (!is_clamp and p.take(')')) return first;
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
    fn mathFunction(p: *Parser, name: []const u8) anyerror!?Quantity {
        const trigonometry = .{
            .{ "sin", math.Trig.sin },   .{ "cos", math.Trig.cos },   .{ "tan", math.Trig.tan },
            .{ "asin", math.Trig.asin }, .{ "acos", math.Trig.acos }, .{ "atan", math.Trig.atan },
        };
        inline for (trigonometry) |entry| {
            if (std.ascii.eqlIgnoreCase(name, entry[0])) {
                const argument = try p.expression();
                const inverse = entry[1] == .asin or entry[1] == .acos or entry[1] == .atan;
                if (argument.dimension != .number and (inverse or argument.dimension != .angle)) return error.IncompatibleDimensions;
                if (!p.take(')')) return error.InvalidLength;
                return .{
                    .dimension = if (inverse) .angle else .number,
                    .value = if (argument.value) |v| math.trig(v, argument.dimension == .angle, entry[1]) else null,
                };
            }
        }
        if (std.ascii.eqlIgnoreCase(name, "atan2")) {
            const y = try p.expression();
            if (!p.take(',')) return error.InvalidLength;
            const x = try p.expression();
            if (y.dimension != x.dimension) return error.IncompatibleDimensions;
            if (!p.take(')')) return error.InvalidLength;
            return .{ .dimension = .angle, .value = if (y.value != null and x.value != null) math.atan2(y.value.?, x.value.?) else null };
        }
        const is_round = std.ascii.eqlIgnoreCase(name, "round");
        const is_mod = std.ascii.eqlIgnoreCase(name, "mod");
        const is_rem = std.ascii.eqlIgnoreCase(name, "rem");
        if (is_round or is_mod or is_rem) {
            var strategy: math.RoundStrategy = .nearest;
            if (is_round) {
                p.whitespace();
                const strategy_start = p.pos;
                while (p.pos < p.input.len and (std.ascii.isAlphabetic(p.input[p.pos]) or p.input[p.pos] == '-')) : (p.pos += 1) {}
                const token = p.input[strategy_start..p.pos];
                const strategies = .{ .{ "nearest", math.RoundStrategy.nearest }, .{ "up", math.RoundStrategy.up }, .{ "down", math.RoundStrategy.down }, .{ "to-zero", math.RoundStrategy.to_zero } };
                var found = false;
                inline for (strategies) |entry| {
                    if (std.ascii.eqlIgnoreCase(token, entry[0])) {
                        strategy = entry[1];
                        found = true;
                    }
                }
                if (found) {
                    if (!p.take(',')) return error.InvalidLength;
                } else p.pos = strategy_start;
            }
            var a = try p.expression();
            var b = Quantity{ .dimension = .number, .value = 1 };
            if (p.take(',')) {
                b = try p.expression();
            } else if (!is_round or a.dimension != .number) return error.InvalidLength;
            if (a.dimension != b.dimension) return error.IncompatibleDimensions;
            if (!p.take(')')) return error.InvalidLength;
            a.value = if (a.value != null and b.value != null)
                (if (is_round) math.round(a.value.?, b.value.?, strategy) else math.remainder(a.value.?, b.value.?, is_mod))
            else
                null;
            return a;
        }
        if (std.ascii.eqlIgnoreCase(name, "hypot")) {
            var result = try p.expression();
            if (result.value) |v| result.value = @abs(v);
            while (p.take(',')) {
                const next = try p.expression();
                if (next.dimension != result.dimension) return error.IncompatibleDimensions;
                result.value = if (result.value != null and next.value != null)
                    (if (std.math.isNan(result.value.?) or std.math.isNan(next.value.?)) std.math.nan(f32) else std.math.hypot(result.value.?, next.value.?))
                else
                    null;
            }
            if (!p.take(')')) return error.InvalidLength;
            return result;
        }
        const is_pow = std.ascii.eqlIgnoreCase(name, "pow");
        const is_log = std.ascii.eqlIgnoreCase(name, "log");
        const is_exp = std.ascii.eqlIgnoreCase(name, "exp");
        const is_sqrt = std.ascii.eqlIgnoreCase(name, "sqrt");
        if (is_pow or is_log or is_exp or is_sqrt) {
            var a = try p.expression();
            if (a.dimension != .number) return error.IncompatibleDimensions;
            var b = Quantity{ .dimension = .number, .value = std.math.e };
            if (is_pow) {
                if (!p.take(',')) return error.InvalidLength;
                b = try p.expression();
            } else if (is_log and p.take(',')) b = try p.expression();
            if (b.dimension != .number) return error.IncompatibleDimensions;
            if (!p.take(')')) return error.InvalidLength;
            if (a.value) |v| {
                a.value = if (is_pow)
                    (if (b.value) |exponent| math.power(v, exponent) else null)
                else if (is_log)
                    (if (b.value) |base| math.logarithm(v, base) else null)
                else if (is_sqrt)
                    (if (v < 0) std.math.nan(f32) else @sqrt(v))
                else
                    @exp(v);
            }
            return a;
        }
        return null;
    }
    fn unit(p: *Parser, value: f32, u: []const u8) !?f32 {
        const c = p.context;
        const fixed = .{ .{ "px", 1.0 }, .{ "in", 96.0 }, .{ "cm", 96.0 / 2.54 }, .{ "mm", 96.0 / 25.4 }, .{ "q", 96.0 / 101.6 }, .{ "pt", 96.0 / 72.0 }, .{ "pc", 16.0 } };
        inline for (fixed) |pair| if (std.ascii.eqlIgnoreCase(u, pair[0])) return value * pair[1];
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
        inline for (relatives) |pair| if (std.ascii.eqlIgnoreCase(u, pair[0])) return scaled(value, pair[1], pair[2]);
        return error.UnsupportedUnit;
    }
};

pub const UpdateFrequency = enum {
    none,
    slow,
    fast,
};

/// Evaluates the CSS update frequency media query feature: (update: fast | slow | none) or (update)
pub fn evaluateUpdateMediaQuery(query: []const u8, current_frequency: UpdateFrequency) bool {
    const trimmed = std.mem.trim(u8, query, " \t\r\n()");
    if (std.ascii.eqlIgnoreCase(trimmed, "update")) {
        return current_frequency != .none;
    }
    if (std.ascii.startsWithIgnoreCase(trimmed, "update:")) {
        const val = std.mem.trim(u8, trimmed[7..], " \t\r\n");
        if (std.ascii.eqlIgnoreCase(val, "fast")) return current_frequency == .fast;
        if (std.ascii.eqlIgnoreCase(val, "slow")) return current_frequency == .slow;
        if (std.ascii.eqlIgnoreCase(val, "none")) return current_frequency == .none;
    }
    return false;
}

