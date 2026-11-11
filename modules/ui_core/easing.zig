//! Literal CSS easing functions. Math expressions and escaped identifiers are
//! resolved by the caller; malformed literals never become partial curves.
const std = @import("std");
pub const ParseError = error{InvalidTimingFunction};
const invalid = error.InvalidTimingFunction;

pub const CubicBezier = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    pub const linear: CubicBezier = .{ .x1 = 0, .y1 = 0, .x2 = 1, .y2 = 1 };
    pub const ease: CubicBezier = .{ .x1 = 0.25, .y1 = 0.1, .x2 = 0.25, .y2 = 1 };
    pub const ease_in: CubicBezier = .{ .x1 = 0.42, .y1 = 0, .x2 = 1, .y2 = 1 };
    pub const ease_out: CubicBezier = .{ .x1 = 0, .y1 = 0, .x2 = 0.58, .y2 = 1 };
    pub const ease_in_out: CubicBezier = .{ .x1 = 0.42, .y1 = 0, .x2 = 0.58, .y2 = 1 };

    fn sample(t: f64, p1: f64, p2: f64) f64 {
        const inv = 1 - t;
        return 3 * inv * inv * t * p1 + 3 * inv * t * t * p2 + t * t * t;
    }

    /// Inverts the x curve, preserving y overshoot and endpoint tangents.
    pub fn solve(self: CubicBezier, progress: f32) f32 {
        const x: f64 = progress;
        if (x < 0) {
            if (self.x1 > 0) return @floatCast(x * self.y1 / self.x1);
            if (self.x2 > 0) return @floatCast(x * self.y2 / self.x2);
            return 0;
        }
        if (x > 1) {
            if (self.x2 < 1) return @floatCast(1 + (x - 1) * (1 - @as(f64, self.y2)) / (1 - @as(f64, self.x2)));
            if (self.x1 < 1) return @floatCast(1 + (x - 1) * (1 - @as(f64, self.y1)) / (1 - @as(f64, self.x1)));
            return 1;
        }
        if (x == 0 or x == 1) return progress;
        if (self.x1 == self.y1 and self.x2 == self.y2) return progress;
        var lo: f64 = 0;
        var hi: f64 = 1;
        // Bounded bisection also handles zero derivatives and flat x tangents.
        for (0..64) |_| {
            const t = (lo + hi) / 2;
            if (t == lo or t == hi) break;
            if (sample(t, self.x1, self.x2) < x) lo = t else hi = t;
        }
        return @floatCast(sample((lo + hi) / 2, self.y1, self.y2));
    }
};

const Parser = struct {
    input: []const u8,
    pos: usize = 0,

    fn whitespace(self: *Parser) ParseError!void {
        while (self.pos < self.input.len) {
            if (std.mem.indexOfScalar(u8, " \t\n\r\x0c", self.input[self.pos]) != null) {
                self.pos += 1;
            } else if (std.mem.startsWith(u8, self.input[self.pos..], "/*")) {
                const end = std.mem.indexOf(u8, self.input[self.pos + 2 ..], "*/") orelse return invalid;
                self.pos += end + 4;
            } else break;
        }
    }

    fn take(self: *Parser, c: u8) ParseError!bool {
        try self.whitespace();
        if (self.pos == self.input.len or self.input[self.pos] != c) return false;
        self.pos += 1;
        return true;
    }

    fn expect(self: *Parser, c: u8) ParseError!void {
        if (!try self.take(c)) return invalid;
    }

    fn end(self: *Parser) ParseError!void {
        try self.whitespace();
        if (self.pos != self.input.len) return invalid;
    }

    fn ident(self: *Parser) ParseError![]const u8 {
        try self.whitespace();
        const start = self.pos;
        while (self.pos < self.input.len and (std.ascii.isAlphabetic(self.input[self.pos]) or self.input[self.pos] == '-')) self.pos += 1;
        if (start == self.pos) return invalid;
        return self.input[start..self.pos];
    }

    fn numberToken(self: *Parser, integer: bool) ParseError![]const u8 {
        try self.whitespace();
        const start = self.pos;
        if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) self.pos += 1;
        const digits = self.pos;
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) self.pos += 1;
        var has_digits = self.pos != digits;
        if (!integer and self.pos + 1 < self.input.len and self.input[self.pos] == '.' and std.ascii.isDigit(self.input[self.pos + 1])) {
            self.pos += 1;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) self.pos += 1;
            has_digits = true;
        }
        if (!has_digits) return invalid;
        if (!integer and self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) self.pos += 1;
            const exponent = self.pos;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) self.pos += 1;
            if (exponent == self.pos) return invalid;
        }
        return self.input[start..self.pos];
    }

    fn number(self: *Parser) ParseError!f64 {
        const value = std.fmt.parseFloat(f64, try self.numberToken(false)) catch return invalid;
        if (!std.math.isFinite(value) or @abs(value) > std.math.floatMax(f32)) return invalid;
        return value;
    }
};

fn is(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub fn parseNumberStrict(value: []const u8) ParseError!f32 {
    var p = Parser{ .input = value };
    const result = try p.number();
    try p.end();
    return @floatCast(result);
}

fn keyword(name: []const u8) ?CubicBezier {
    if (is(name, "linear")) return CubicBezier.linear;
    if (is(name, "ease")) return CubicBezier.ease;
    if (is(name, "ease-in")) return CubicBezier.ease_in;
    if (is(name, "ease-out")) return CubicBezier.ease_out;
    if (is(name, "ease-in-out")) return CubicBezier.ease_in_out;
    return null;
}

fn bezier(p: *Parser) ParseError!CubicBezier {
    const x1 = try p.number();
    try p.expect(',');
    const y1 = try p.number();
    try p.expect(',');
    const x2 = try p.number();
    try p.expect(',');
    const y2 = try p.number();
    try p.expect(')');
    try p.end();
    if (x1 < 0 or x1 > 1 or x2 < 0 or x2 > 1) return invalid;
    return .{ .x1 = @floatCast(x1), .y1 = @floatCast(y1), .x2 = @floatCast(x2), .y2 = @floatCast(y2) };
}

pub fn parseTimingFunctionStrict(value: []const u8) ParseError!CubicBezier {
    var p = Parser{ .input = value };
    const name = try p.ident();
    if (keyword(name)) |curve| {
        try p.end();
        return curve;
    }
    // A CSS function token requires '(' directly after its identifier.
    if (!is(name, "cubic-bezier") or p.pos == value.len or value[p.pos] != '(') return invalid;
    p.pos += 1;
    return bezier(&p);
}

/// Compatibility helper: malformed literals fall back to ease.
pub fn parseTimingFunction(value: []const u8) CubicBezier {
    return parseTimingFunctionStrict(value) catch CubicBezier.ease;
}

pub const LinearPoint = struct { input: f64, output: f64 };
const RawPoint = struct { input: ?f64, output: f64 };

// Produces raw points without allocation; two percentages expand into two points.
const RawLinear = struct {
    parser: Parser,
    extra: ?RawPoint = null,
    done: bool = false,
    stops: usize = 0,

    fn next(self: *RawLinear) ParseError!?RawPoint {
        if (self.extra) |point| {
            self.extra = null;
            return point;
        }
        if (self.done) return null;
        var output: ?f64 = null;
        var inputs: [2]f64 = undefined;
        var count: usize = 0;
        var leading_inputs = false;
        while (true) {
            const number = try self.parser.number();
            // '%' is part of the numeric token and cannot follow whitespace.
            if (self.parser.pos < self.parser.input.len and self.parser.input[self.parser.pos] == '%') {
                self.parser.pos += 1;
                if (count == inputs.len or leading_inputs) return invalid;
                inputs[count] = number / 100;
                count += 1;
            } else {
                if (output != null) return invalid;
                output = number;
                leading_inputs = count != 0;
            }
            const token_end = self.parser.pos;
            try self.parser.whitespace();
            if (try self.parser.take(',')) break;
            if (try self.parser.take(')')) {
                try self.parser.end();
                self.done = true;
                break;
            }
            if (token_end == self.parser.pos) return invalid;
        }
        const y = output orelse return invalid;
        self.stops += 1;
        if (count == 2) self.extra = .{ .input = inputs[1], .output = y };
        return .{ .input = if (count == 0) null else inputs[0], .output = y };
    }
};

// Resolve omitted positions by looking ahead to the next explicit position.
// A borrowed curve can consequently be sampled without heap allocations or caps.
const LinearIterator = struct {
    raw: RawLinear,
    previous: ?f64 = null,
    run_end: f64 = 0,
    run_start: f64 = 0,
    run_size: usize = 0,
    run_index: usize = 0,

    fn next(self: *LinearIterator) ParseError!?LinearPoint {
        const point = (try self.raw.next()) orelse return null;
        var x = point.input;
        if (x == null and self.previous == null) x = 0;
        if (x == null and self.raw.done and self.raw.extra == null) x = 1;
        if (x) |value| {
            const position = if (self.previous) |previous| @max(previous, value) else value;
            self.previous = position;
            return .{ .input = position, .output = point.output };
        }
        if (self.run_index == self.run_size) {
            var lookahead = self.raw;
            var missing: usize = 1;
            while (try lookahead.next()) |following| {
                var end = following.input;
                if (end == null and lookahead.done and lookahead.extra == null) end = 1;
                if (end) |value| {
                    self.run_end = @max(self.previous.?, value);
                    break;
                }
                missing += 1;
            }
            self.run_start = self.previous.?;
            self.run_size = missing;
            self.run_index = 0;
        }
        self.run_index += 1;
        const fraction = @as(f64, @floatFromInt(self.run_index)) / @as(f64, @floatFromInt(self.run_size + 1));
        const position = self.run_start + (self.run_end - self.run_start) * fraction;
        self.previous = position;
        return .{ .input = position, .output = point.output };
    }
};

pub const LinearEasing = struct {
    /// parseStrict owns points; parse borrows source until its last evaluation.
    points: []const LinearPoint = &.{},
    source: ?[]const u8 = null,

    pub fn solve(self: LinearEasing, progress: f32, before: bool) f32 {
        var iterator = LinearIterator{ .raw = .{ .parser = .{ .input = self.source orelse "" } } };
        var index: usize = 0;
        var first: ?LinearPoint = null;
        var previous: ?LinearPoint = null;
        var previous_previous: ?LinearPoint = null;
        var exact: ?f64 = null;
        const x: f64 = progress;
        while (true) {
            const point = if (self.source != null) (iterator.next() catch return progress) else if (index < self.points.len) self.points[index] else null;
            const b = point orelse break;
            index += 1;
            if (first == null) {
                first = b;
                if (before and x == b.input) return @floatCast(b.output);
            }
            if (x == b.input) exact = b.output;
            if (previous) |a| {
                if (x < first.?.input) return interpolate(a, b, x, true);
            }
            if (x < b.input) {
                if (exact) |output| return @floatCast(output);
                if (previous) |a| return interpolate(a, b, x, false);
                // Need the first two points for extrapolation on the left.
            }
            previous_previous = previous;
            previous = b;
        }
        if (exact) |output| return @floatCast(output);
        const b = previous orelse return progress;
        const a = previous_previous orelse return @floatCast(b.output);
        return interpolate(a, b, x, false);
    }

    fn interpolate(a: LinearPoint, b: LinearPoint, x: f64, left: bool) f32 {
        if (a.input == b.input) return @floatCast(if (left) a.output else b.output);
        return @floatCast(a.output + (b.output - a.output) * ((x - a.input) / (b.input - a.input)));
    }
};

pub const StepPosition = enum { start, end, none, both };
pub const Steps = struct {
    count: u32,
    jump: StepPosition = .end,

    pub fn solve(self: Steps, progress: f32, before: bool) f32 {
        if (self.count == 0 or (self.jump == .none and self.count < 2)) return progress;
        const n: f64 = @floatFromInt(self.count);
        const x: f64 = progress;
        const scaled = x * n;
        var step = @floor(scaled);
        if (self.jump == .start or self.jump == .both) step += 1;
        if (before and scaled == @floor(scaled)) step -= 1;
        if (x >= 0 and step < 0) step = 0;
        const jumps = n + @as(f64, if (self.jump == .both) 1 else if (self.jump == .none) -1 else 0);
        if (x <= 1 and step > jumps) step = jumps;
        return @floatCast(step / jumps);
    }
};

pub const Timing = union(enum) {
    bezier: CubicBezier,
    steps: Steps,
    linear: LinearEasing,

    /// Allocation-free compatibility API. linear() borrows the supplied text;
    /// use parseStrict when the curve must outlive that text or reject invalid CSS.
    pub fn parse(value: []const u8) Timing {
        return parseBorrowed(value) catch .{ .bezier = CubicBezier.ease };
    }

    fn parseBorrowed(value: []const u8) ParseError!Timing {
        var p = Parser{ .input = value };
        const name = try p.ident();
        if (keyword(name)) |curve| {
            try p.end();
            return .{ .bezier = curve };
        }
        if (is(name, "step-start") or is(name, "step-end")) {
            try p.end();
            return .{ .steps = .{ .count = 1, .jump = if (is(name, "step-start")) .start else .end } };
        }
        if (p.pos == value.len or value[p.pos] != '(') return invalid;
        p.pos += 1;
        if (is(name, "cubic-bezier")) return .{ .bezier = try bezier(&p) };
        if (is(name, "steps")) {
            const count_text = try p.numberToken(true);
            const unsigned = if (count_text[0] == '+') count_text[1..] else count_text;
            const count = std.fmt.parseInt(u32, unsigned, 10) catch return invalid;
            var jump: StepPosition = .end;
            if (try p.take(',')) {
                const position = try p.ident();
                jump = if (is(position, "start") or is(position, "jump-start")) .start else if (is(position, "end") or is(position, "jump-end")) .end else if (is(position, "jump-none")) .none else if (is(position, "jump-both")) .both else return invalid;
            }
            try p.expect(')');
            try p.end();
            if (count == 0 or (jump == .none and count < 2)) return invalid;
            return .{ .steps = .{ .count = count, .jump = jump } };
        }
        if (!is(name, "linear")) return invalid;
        const source = value[p.pos..];
        var iterator = LinearIterator{ .raw = .{ .parser = .{ .input = source } } };
        while (try iterator.next()) |_| {}
        if (iterator.raw.stops < 2) return invalid;
        return .{ .linear = .{ .source = source } };
    }

    /// Returns an owned curve. Release with deinit using the same allocator;
    /// copying this value does not transfer or duplicate its ownership.
    pub fn parseStrict(allocator: std.mem.Allocator, value: []const u8) (ParseError || std.mem.Allocator.Error)!Timing {
        const borrowed = try parseBorrowed(value);
        if (borrowed != .linear) return borrowed;
        var points: std.ArrayList(LinearPoint) = .empty;
        defer points.deinit(allocator);
        var iterator = LinearIterator{ .raw = .{ .parser = .{ .input = borrowed.linear.source.? } } };
        while (try iterator.next()) |point| try points.append(allocator, point);
        return .{ .linear = .{ .points = try points.toOwnedSlice(allocator) } };
    }

    pub fn deinit(self: *Timing, allocator: std.mem.Allocator) void {
        if (self.* == .linear and self.linear.source == null) allocator.free(self.linear.points);
        self.* = .{ .bezier = CubicBezier.ease };
    }

    pub fn solve(self: Timing, progress: f32) f32 {
        return self.solveBefore(progress, false);
    }

    pub fn solveBefore(self: Timing, progress: f32, before: bool) f32 {
        return switch (self) {
            .bezier => |curve| curve.solve(progress),
            .steps => |curve| curve.solve(progress, before),
            .linear => |curve| curve.solve(progress, before),
        };
    }
};
