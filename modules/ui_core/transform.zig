//! 2D Transform matrix calculations and CSS transform parser.
const std = @import("std");

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Matrix2D = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,

    pub const identity: Matrix2D = .{
        .a = 1,
        .b = 0,
        .c = 0,
        .d = 1,
        .tx = 0,
        .ty = 0,
    };

    pub fn multiply(self: Matrix2D, other: Matrix2D) Matrix2D {
        return .{
            .a = self.a * other.a + self.c * other.b,
            .b = self.b * other.a + self.d * other.b,
            .c = self.a * other.c + self.c * other.d,
            .d = self.b * other.c + self.d * other.d,
            .tx = self.a * other.tx + self.c * other.ty + self.tx,
            .ty = self.b * other.tx + self.d * other.ty + self.ty,
        };
    }

    pub fn makeTranslate(tx: f32, ty: f32) Matrix2D {
        return .{
            .a = 1,
            .b = 0,
            .c = 0,
            .d = 1,
            .tx = tx,
            .ty = ty,
        };
    }

    pub fn makeScale(sx: f32, sy: f32) Matrix2D {
        return .{
            .a = sx,
            .b = 0,
            .c = 0,
            .d = sy,
            .tx = 0,
            .ty = 0,
        };
    }

    pub fn makeRotate(rad: f32) Matrix2D {
        const cos = @cos(rad);
        const sin = @sin(rad);
        return .{
            .a = cos,
            .b = sin,
            .c = -sin,
            .d = cos,
            .tx = 0,
            .ty = 0,
        };
    }

    pub fn makeSkew(ax_rad: f32, ay_rad: f32) Matrix2D {
        return .{
            .a = 1,
            .b = @tan(ay_rad),
            .c = @tan(ax_rad),
            .d = 1,
            .tx = 0,
            .ty = 0,
        };
    }

    pub fn transformPoint(self: Matrix2D, p: Point) Point {
        return .{
            .x = self.a * p.x + self.c * p.y + self.tx,
            .y = self.b * p.x + self.d * p.y + self.ty,
        };
    }

    pub fn inverse(self: Matrix2D) ?Matrix2D {
        const det = self.a * self.d - self.b * self.c;
        if (@abs(det) < 1e-6) return null;
        const inv_det = 1.0 / det;
        return .{
            .a = self.d * inv_det,
            .b = -self.b * inv_det,
            .c = -self.c * inv_det,
            .d = self.a * inv_det,
            .tx = (self.c * self.ty - self.d * self.tx) * inv_det,
            .ty = (self.b * self.tx - self.a * self.ty) * inv_det,
        };
    }

    /// Transforms a point with respect to a transform origin.
    pub fn transformPointWithOrigin(self: Matrix2D, origin: Point, p: Point) Point {
        // translate point to origin -> apply matrix -> translate back
        const rel: Point = .{ .x = p.x - origin.x, .y = p.y - origin.y };
        const transformed = self.transformPoint(rel);
        return .{ .x = transformed.x + origin.x, .y = transformed.y + origin.y };
    }

    /// Inverse transforms a point with respect to a transform origin.
    pub fn inverseTransformPointWithOrigin(self: Matrix2D, origin: Point, p: Point) ?Point {
        const inv = self.inverse() orelse return null;
        const rel: Point = .{ .x = p.x - origin.x, .y = p.y - origin.y };
        const transformed = inv.transformPoint(rel);
        return .{ .x = transformed.x + origin.x, .y = transformed.y + origin.y };
    }
};

fn parseAngle(str: []const u8) !f32 {
    const trimmed = std.mem.trim(u8, str, " \t\r\n");
    if (std.mem.endsWith(u8, trimmed, "deg")) {
        const num = try std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 3]);
        return num * (std.math.pi / 180.0);
    } else if (std.mem.endsWith(u8, trimmed, "rad")) {
        return try std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 3]);
    } else if (std.mem.endsWith(u8, trimmed, "turn")) {
        const num = try std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 4]);
        return num * (2.0 * std.math.pi);
    } else {
        // Plain number defaults to radians or degrees? In CSS deg is standard for angle properties.
        const num = try std.fmt.parseFloat(f32, trimmed);
        return num * (std.math.pi / 180.0);
    }
}

fn parseLength(str: []const u8) !f32 {
    const trimmed = std.mem.trim(u8, str, " \t\r\n");
    if (std.mem.endsWith(u8, trimmed, "px")) {
        return try std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 2]);
    }
    return try std.fmt.parseFloat(f32, trimmed);
}

/// Parses a 2D CSS transform string into a cumulative Matrix2D.
pub fn parseTransform(css: []const u8) !Matrix2D {
    var res = Matrix2D.identity;
    var i: usize = 0;
    const len = css.len;

    while (i < len) {
        // Skip whitespace and commas
        while (i < len and (css[i] == ' ' or css[i] == '\t' or css[i] == ',' or css[i] == '\r' or css[i] == '\n')) : (i += 1) {}
        if (i >= len) break;

        const fn_start = i;
        while (i < len and css[i] != '(' and css[i] != ' ') : (i += 1) {}
        const fn_name = css[fn_start..i];

        while (i < len and css[i] != '(') : (i += 1) {}
        if (i >= len) break;
        i += 1; // skip '('

        const args_start = i;
        var paren_depth: usize = 1;
        while (i < len and paren_depth > 0) : (i += 1) {
            if (css[i] == '(') paren_depth += 1;
            if (css[i] == ')') paren_depth -= 1;
        }
        const args_end = if (i > 0) i - 1 else args_start;
        const args_str = css[args_start..args_end];

        var args_it = std.mem.tokenizeAny(u8, args_str, ", \t");

        if (std.mem.eql(u8, fn_name, "translate")) {
            const tx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tx = try parseLength(tx_str);
            const ty_str = args_it.next();
            const ty = if (ty_str) |s| try parseLength(s) else 0;
            res = res.multiply(Matrix2D.makeTranslate(tx, ty));
        } else if (std.mem.eql(u8, fn_name, "translateX")) {
            const tx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tx = try parseLength(tx_str);
            res = res.multiply(Matrix2D.makeTranslate(tx, 0));
        } else if (std.mem.eql(u8, fn_name, "translateY")) {
            const ty_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ty = try parseLength(ty_str);
            res = res.multiply(Matrix2D.makeTranslate(0, ty));
        } else if (std.mem.eql(u8, fn_name, "scale")) {
            const sx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sx = try std.fmt.parseFloat(f32, std.mem.trim(u8, sx_str, " "));
            const sy_str = args_it.next();
            const sy = if (sy_str) |s| try std.fmt.parseFloat(f32, std.mem.trim(u8, s, " ")) else sx;
            res = res.multiply(Matrix2D.makeScale(sx, sy));
        } else if (std.mem.eql(u8, fn_name, "scaleX")) {
            const sx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sx = try std.fmt.parseFloat(f32, std.mem.trim(u8, sx_str, " "));
            res = res.multiply(Matrix2D.makeScale(sx, 1));
        } else if (std.mem.eql(u8, fn_name, "scaleY")) {
            const sy_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sy = try std.fmt.parseFloat(f32, std.mem.trim(u8, sy_str, " "));
            res = res.multiply(Matrix2D.makeScale(1, sy));
        } else if (std.mem.eql(u8, fn_name, "rotate")) {
            const angle_str = args_it.next() orelse return error.InvalidTransformArgs;
            const rad = try parseAngle(angle_str);
            res = res.multiply(Matrix2D.makeRotate(rad));
        } else if (std.mem.eql(u8, fn_name, "skew")) {
            const ax_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ax = try parseAngle(ax_str);
            const ay_str = args_it.next();
            const ay = if (ay_str) |s| try parseAngle(s) else 0;
            res = res.multiply(Matrix2D.makeSkew(ax, ay));
        } else if (std.mem.eql(u8, fn_name, "skewX")) {
            const ax_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ax = try parseAngle(ax_str);
            res = res.multiply(Matrix2D.makeSkew(ax, 0));
        } else if (std.mem.eql(u8, fn_name, "skewY")) {
            const ay_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ay = try parseAngle(ay_str);
            res = res.multiply(Matrix2D.makeSkew(0, ay));
        } else if (std.mem.eql(u8, fn_name, "matrix")) {
            const a = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const b = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const c = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const d = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const tx = try parseLength(args_it.next() orelse return error.InvalidTransformArgs);
            const ty = try parseLength(args_it.next() orelse return error.InvalidTransformArgs);
            const mat: Matrix2D = .{ .a = a, .b = b, .c = c, .d = d, .tx = tx, .ty = ty };
            res = res.multiply(mat);
        }
    }

    return res;
}

/// Parses transform-origin (e.g. "50% 50%", "center", "left top", "0 0") relative to box dimensions.
pub fn parseTransformOrigin(css: []const u8, width: f32, height: f32) Point {
    if (css.len == 0) return .{ .x = width * 0.5, .y = height * 0.5 };
    var it = std.mem.tokenizeAny(u8, css, " \t,");
    const part1 = it.next() orelse return .{ .x = width * 0.5, .y = height * 0.5 };
    const part2 = it.next() orelse part1;

    const parseSide = struct {
        fn get(str: []const u8, size: f32) f32 {
            const trimmed = std.mem.trim(u8, str, " ");
            if (std.mem.eql(u8, trimmed, "center")) return size * 0.5;
            if (std.mem.eql(u8, trimmed, "left") or std.mem.eql(u8, trimmed, "top")) return 0;
            if (std.mem.eql(u8, trimmed, "right") or std.mem.eql(u8, trimmed, "bottom")) return size;
            if (std.mem.endsWith(u8, trimmed, "%")) {
                const pct = std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 1]) catch 50;
                return size * (pct / 100.0);
            }
            if (std.mem.endsWith(u8, trimmed, "px")) {
                return std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 2]) catch 0;
            }
            return std.fmt.parseFloat(f32, trimmed) catch 0;
        }
    }.get;

    return .{
        .x = parseSide(part1, width),
        .y = parseSide(part2, height),
    };
}
