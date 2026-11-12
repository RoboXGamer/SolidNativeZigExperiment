//! 2D and 3D Transform matrix calculations and CSS transform parser.
const std = @import("std");

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Point3D = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
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

/// 4x4 Matrix for 3D transforms, compatible with OpenGL/raylib column-major memory layout.
pub const Matrix4x4 = struct {
    m: [16]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },

    pub const identity: Matrix4x4 = .{};

    pub fn from2D(m2: Matrix2D) Matrix4x4 {
        return .{
            .m = .{
                m2.a,  m2.b,  0, 0,
                m2.c,  m2.d,  0, 0,
                0,     0,     1, 0,
                m2.tx, m2.ty, 0, 1,
            },
        };
    }

    pub fn to2D(self: Matrix4x4) Matrix2D {
        return .{
            .a = self.m[0],
            .b = self.m[1],
            .c = self.m[4],
            .d = self.m[5],
            .tx = self.m[12],
            .ty = self.m[13],
        };
    }

    pub fn multiply(self: Matrix4x4, other: Matrix4x4) Matrix4x4 {
        var res = Matrix4x4{ .m = undefined };
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) {
                    sum += self.m[row + k * 4] * other.m[k + col * 4];
                }
                res.m[row + col * 4] = sum;
            }
        }
        return res;
    }

    pub fn makeTranslate3D(tx: f32, ty: f32, tz: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        res.m[12] = tx;
        res.m[13] = ty;
        res.m[14] = tz;
        return res;
    }

    pub fn makeScale3D(sx: f32, sy: f32, sz: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        res.m[0] = sx;
        res.m[5] = sy;
        res.m[10] = sz;
        return res;
    }

    pub fn makeRotateX(rad: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[5] = c;
        res.m[6] = s;
        res.m[9] = -s;
        res.m[10] = c;
        return res;
    }

    pub fn makeRotateY(rad: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[0] = c;
        res.m[2] = -s;
        res.m[8] = s;
        res.m[10] = c;
        return res;
    }

    pub fn makeRotateZ(rad: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        const c = @cos(rad);
        const s = @sin(rad);
        res.m[0] = c;
        res.m[1] = s;
        res.m[4] = -s;
        res.m[5] = c;
        return res;
    }

    pub fn makeRotate3D(x: f32, y: f32, z: f32, rad: f32) Matrix4x4 {
        const len = @sqrt(x * x + y * y + z * z);
        if (len < 1e-6) return Matrix4x4.identity;
        const nx = x / len;
        const ny = y / len;
        const nz = z / len;
        const c = @cos(rad);
        const s = @sin(rad);
        const t = 1.0 - c;

        var res = Matrix4x4.identity;
        res.m[0] = t * nx * nx + c;
        res.m[1] = t * nx * ny + s * nz;
        res.m[2] = t * nx * nz - s * ny;

        res.m[4] = t * nx * ny - s * nz;
        res.m[5] = t * ny * ny + c;
        res.m[6] = t * ny * nz + s * nx;

        res.m[8] = t * nx * nz + s * ny;
        res.m[9] = t * ny * nz - s * nx;
        res.m[10] = t * nz * nz + c;
        return res;
    }

    pub fn makePerspective(d: f32) Matrix4x4 {
        var res = Matrix4x4.identity;
        if (d > 0) {
            res.m[11] = -1.0 / d;
        }
        return res;
    }

    pub fn transformPoint3D(self: Matrix4x4, p: Point3D) Point3D {
        const x = self.m[0] * p.x + self.m[4] * p.y + self.m[8] * p.z + self.m[12];
        const y = self.m[1] * p.x + self.m[5] * p.y + self.m[9] * p.z + self.m[13];
        const z = self.m[2] * p.x + self.m[6] * p.y + self.m[10] * p.z + self.m[14];
        const w = self.m[3] * p.x + self.m[7] * p.y + self.m[11] * p.z + self.m[15];
        if (@abs(w) > 1e-6 and w != 1.0) {
            const inv_w = 1.0 / w;
            return .{ .x = x * inv_w, .y = y * inv_w, .z = z * inv_w };
        }
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn isBackface(self: Matrix4x4) bool {
        const det2d = self.m[0] * self.m[5] - self.m[1] * self.m[4];
        return det2d < 0;
    }

    pub fn inverse(self: Matrix4x4) ?Matrix4x4 {
        const a = self.m;
        var out = Matrix4x4{ .m = undefined };

        const b00 = a[0] * a[5] - a[1] * a[4];
        const b01 = a[0] * a[6] - a[2] * a[4];
        const b02 = a[0] * a[7] - a[3] * a[4];
        const b03 = a[1] * a[6] - a[2] * a[5];
        const b04 = a[1] * a[7] - a[3] * a[5];
        const b05 = a[2] * a[7] - a[3] * a[6];
        const b06 = a[8] * a[13] - a[9] * a[12];
        const b07 = a[8] * a[14] - a[10] * a[12];
        const b08 = a[8] * a[15] - a[11] * a[12];
        const b09 = a[9] * a[14] - a[10] * a[13];
        const b10 = a[9] * a[15] - a[11] * a[13];
        const b11 = a[10] * a[15] - a[11] * a[14];

        const det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
        if (@abs(det) < 1e-6) return null;
        const inv_det = 1.0 / det;

        out.m[0] = (a[5] * b11 - a[6] * b10 + a[7] * b09) * inv_det;
        out.m[1] = (-a[1] * b11 + a[2] * b10 - a[3] * b09) * inv_det;
        out.m[2] = (a[13] * b05 - a[14] * b04 + a[15] * b03) * inv_det;
        out.m[3] = (-a[9] * b05 + a[10] * b04 - a[11] * b03) * inv_det;

        out.m[4] = (-a[4] * b11 + a[6] * b08 - a[7] * b07) * inv_det;
        out.m[5] = (a[0] * b11 - a[2] * b08 + a[3] * b07) * inv_det;
        out.m[6] = (-a[12] * b05 + a[14] * b02 - a[15] * b01) * inv_det;
        out.m[7] = (a[8] * b05 - a[10] * b02 + a[11] * b01) * inv_det;

        out.m[8] = (a[4] * b10 - a[5] * b08 + a[7] * b06) * inv_det;
        out.m[9] = (-a[0] * b10 + a[1] * b08 - a[3] * b06) * inv_det;
        out.m[10] = (a[12] * b04 - a[13] * b02 + a[15] * b00) * inv_det;
        out.m[11] = (-a[8] * b04 + a[9] * b02 - a[11] * b00) * inv_det;

        out.m[12] = (-a[4] * b09 + a[5] * b07 - a[6] * b06) * inv_det;
        out.m[13] = (a[0] * b09 - a[1] * b07 + a[2] * b06) * inv_det;
        out.m[14] = (-a[12] * b03 + a[13] * b01 - a[14] * b00) * inv_det;
        out.m[15] = (a[8] * b03 - a[9] * b01 + a[10] * b00) * inv_det;

        return out;
    }
};

fn parseAngle(str: []const u8) !f32 {
    const input = std.mem.trim(u8, str, " \t\r\n");
    if (std.mem.endsWith(u8, input, "%")) {
        const pct = std.fmt.parseFloat(f32, input[0 .. input.len - 1]) catch return error.InvalidTransformArgs;
        return (pct / 100.0) * 2.0 * std.math.pi;
    }
    if (std.fmt.parseFloat(f32, input)) |v| return v * std.math.pi / 180 else |_| {}
    const value = try @import("sizing.zig").resolveValue(input, .{});
    if (value.dimension != .angle) return error.InvalidTransformArgs;
    const degrees = value.value orelse return error.InvalidTransformArgs;
    if (!std.math.isFinite(degrees)) return error.InvalidTransformArgs;
    return degrees * std.math.pi / 180;
}

fn parseLength(str: []const u8) !f32 {
    const input = std.mem.trim(u8, str, " \t\r\n");
    if (std.fmt.parseFloat(f32, input)) |v| return v else |_| {}
    return switch (try @import("sizing.zig").resolve(input, .{})) {
        .length => |v| v,
        else => error.InvalidTransformArgs,
    };
}

/// Parses a 2D or 3D CSS transform string into a cumulative Matrix4x4.
pub fn parseTransformSized4x4(css: []const u8, width: f32, height: f32) !Matrix4x4 {
    const trimmed = std.mem.trim(u8, css, " \t\r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "none")) return Matrix4x4.identity;

    var res = Matrix4x4.identity;
    var i: usize = 0;
    const len = trimmed.len;

    while (i < len) {
        while (i < len and (trimmed[i] == ' ' or trimmed[i] == '\t' or trimmed[i] == ',' or trimmed[i] == '\r' or trimmed[i] == '\n')) : (i += 1) {}
        if (i >= len) break;

        const fn_start = i;
        while (i < len and trimmed[i] != '(' and trimmed[i] != ' ') : (i += 1) {}
        const fn_name = trimmed[fn_start..i];

        while (i < len and trimmed[i] != '(') : (i += 1) {}
        if (i >= len) break;
        i += 1; // skip '('

        const args_start = i;
        var paren_depth: usize = 1;
        while (i < len and paren_depth > 0) : (i += 1) {
            if (trimmed[i] == '(') paren_depth += 1;
            if (trimmed[i] == ')') paren_depth -= 1;
        }
        const args_end = if (i > 0) i - 1 else args_start;
        const args_str = trimmed[args_start..args_end];

        var args_it = @import("css_syntax.zig").Tokens{ .input = args_str, .separators = ", \t" };

        if (std.mem.eql(u8, fn_name, "translate")) {
            const tx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tx = try sizedLength(tx_str, width);
            const ty_str = args_it.next();
            const ty = if (ty_str) |s| try sizedLength(s, height) else 0;
            res = res.multiply(Matrix4x4.makeTranslate3D(tx, ty, 0));
        } else if (std.mem.eql(u8, fn_name, "translateX")) {
            const tx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tx = try parseLength(tx_str);
            res = res.multiply(Matrix4x4.makeTranslate3D(tx, 0, 0));
        } else if (std.mem.eql(u8, fn_name, "translateY")) {
            const ty_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ty = try sizedLength(ty_str, height);
            res = res.multiply(Matrix4x4.makeTranslate3D(0, ty, 0));
        } else if (std.mem.eql(u8, fn_name, "translateZ")) {
            const tz_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tz = try parseLength(tz_str);
            res = res.multiply(Matrix4x4.makeTranslate3D(0, 0, tz));
        } else if (std.mem.eql(u8, fn_name, "translate3d")) {
            const tx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tx = try sizedLength(tx_str, width);
            const ty_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ty = try sizedLength(ty_str, height);
            const tz_str = args_it.next() orelse return error.InvalidTransformArgs;
            const tz = try parseLength(tz_str);
            res = res.multiply(Matrix4x4.makeTranslate3D(tx, ty, tz));
        } else if (std.mem.eql(u8, fn_name, "scale")) {
            const sx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sx = try std.fmt.parseFloat(f32, std.mem.trim(u8, sx_str, " "));
            const sy_str = args_it.next();
            const sy = if (sy_str) |s| try std.fmt.parseFloat(f32, std.mem.trim(u8, s, " ")) else sx;
            res = res.multiply(Matrix4x4.makeScale3D(sx, sy, 1));
        } else if (std.mem.eql(u8, fn_name, "scaleX")) {
            const sx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sx = try std.fmt.parseFloat(f32, std.mem.trim(u8, sx_str, " "));
            res = res.multiply(Matrix4x4.makeScale3D(sx, 1, 1));
        } else if (std.mem.eql(u8, fn_name, "scaleY")) {
            const sy_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sy = try std.fmt.parseFloat(f32, std.mem.trim(u8, sy_str, " "));
            res = res.multiply(Matrix4x4.makeScale3D(1, sy, 1));
        } else if (std.mem.eql(u8, fn_name, "scaleZ")) {
            const sz_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sz = try std.fmt.parseFloat(f32, std.mem.trim(u8, sz_str, " "));
            res = res.multiply(Matrix4x4.makeScale3D(1, 1, sz));
        } else if (std.mem.eql(u8, fn_name, "scale3d")) {
            const sx_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sx = try std.fmt.parseFloat(f32, std.mem.trim(u8, sx_str, " "));
            const sy_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sy = try std.fmt.parseFloat(f32, std.mem.trim(u8, sy_str, " "));
            const sz_str = args_it.next() orelse return error.InvalidTransformArgs;
            const sz = try std.fmt.parseFloat(f32, std.mem.trim(u8, sz_str, " "));
            res = res.multiply(Matrix4x4.makeScale3D(sx, sy, sz));
        } else if (std.mem.eql(u8, fn_name, "rotate") or std.mem.eql(u8, fn_name, "rotateZ")) {
            const angle_str = args_it.next() orelse return error.InvalidTransformArgs;
            const rad = try parseAngle(angle_str);
            res = res.multiply(Matrix4x4.makeRotateZ(rad));
        } else if (std.mem.eql(u8, fn_name, "rotateX")) {
            const angle_str = args_it.next() orelse return error.InvalidTransformArgs;
            const rad = try parseAngle(angle_str);
            res = res.multiply(Matrix4x4.makeRotateX(rad));
        } else if (std.mem.eql(u8, fn_name, "rotateY")) {
            const angle_str = args_it.next() orelse return error.InvalidTransformArgs;
            const rad = try parseAngle(angle_str);
            res = res.multiply(Matrix4x4.makeRotateY(rad));
        } else if (std.mem.eql(u8, fn_name, "rotate3d")) {
            const x_str = args_it.next() orelse return error.InvalidTransformArgs;
            const x = try std.fmt.parseFloat(f32, std.mem.trim(u8, x_str, " "));
            const y_str = args_it.next() orelse return error.InvalidTransformArgs;
            const y = try std.fmt.parseFloat(f32, std.mem.trim(u8, y_str, " "));
            const z_str = args_it.next() orelse return error.InvalidTransformArgs;
            const z = try std.fmt.parseFloat(f32, std.mem.trim(u8, z_str, " "));
            const angle_str = args_it.next() orelse return error.InvalidTransformArgs;
            const rad = try parseAngle(angle_str);
            res = res.multiply(Matrix4x4.makeRotate3D(x, y, z, rad));
        } else if (std.mem.eql(u8, fn_name, "perspective")) {
            const p_str = args_it.next() orelse return error.InvalidTransformArgs;
            const trimmed_p = std.mem.trim(u8, p_str, " \t");
            if (std.ascii.eqlIgnoreCase(trimmed_p, "none")) {
                // Identity
            } else {
                const dist = try parseLength(trimmed_p);
                res = res.multiply(Matrix4x4.makePerspective(dist));
            }
        } else if (std.mem.eql(u8, fn_name, "skew")) {
            const ax_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ax = try parseAngle(ax_str);
            const ay_str = args_it.next();
            const ay = if (ay_str) |s| try parseAngle(s) else 0;
            res = res.multiply(Matrix4x4.from2D(Matrix2D.makeSkew(ax, ay)));
        } else if (std.mem.eql(u8, fn_name, "skewX")) {
            const ax_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ax = try parseAngle(ax_str);
            res = res.multiply(Matrix4x4.from2D(Matrix2D.makeSkew(ax, 0)));
        } else if (std.mem.eql(u8, fn_name, "skewY")) {
            const ay_str = args_it.next() orelse return error.InvalidTransformArgs;
            const ay = try parseAngle(ay_str);
            res = res.multiply(Matrix4x4.from2D(Matrix2D.makeSkew(0, ay)));
        } else if (std.mem.eql(u8, fn_name, "matrix")) {
            const a = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const b = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const c = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const d = try std.fmt.parseFloat(f32, std.mem.trim(u8, args_it.next() orelse return error.InvalidTransformArgs, " "));
            const tx = try parseLength(args_it.next() orelse return error.InvalidTransformArgs);
            const ty = try parseLength(args_it.next() orelse return error.InvalidTransformArgs);
            const mat2: Matrix2D = .{ .a = a, .b = b, .c = c, .d = d, .tx = tx, .ty = ty };
            res = res.multiply(Matrix4x4.from2D(mat2));
        } else if (std.mem.eql(u8, fn_name, "matrix3d")) {
            var m_vals: [16]f32 = undefined;
            var idx: usize = 0;
            while (idx < 16) : (idx += 1) {
                const s = args_it.next() orelse return error.InvalidTransformArgs;
                m_vals[idx] = try std.fmt.parseFloat(f32, std.mem.trim(u8, s, " "));
            }
            res = res.multiply(Matrix4x4{ .m = m_vals });
        }
    }

    return res;
}

/// Parses a 2D CSS transform string into a cumulative Matrix2D.
pub fn parseTransform(css: []const u8) !Matrix2D {
    return parseTransformSized(css, 0, 0);
}

pub fn parseTransformSized(css: []const u8, width: f32, height: f32) !Matrix2D {
    const mat4 = try parseTransformSized4x4(css, width, height);
    return mat4.to2D();
}

/// Parses transform-origin (1, 2, 3, or 4 value syntax) relative to box dimensions.
pub fn parseTransformOrigin3D(css: []const u8, width: f32, height: f32) Point3D {
    if (css.len == 0) return .{ .x = width * 0.5, .y = height * 0.5, .z = 0 };

    var tokens: [4][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, css, " \t,");
    while (it.next()) |tok| {
        if (count < 4) {
            tokens[count] = tok;
            count += 1;
        }
    }

    if (count == 0) return .{ .x = width * 0.5, .y = height * 0.5, .z = 0 };

    const parseSideVal = struct {
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

    // 4-value position syntax: e.g. "right 10px bottom 20px"
    if (count == 4) {
        var x_val: f32 = width * 0.5;
        var y_val: f32 = height * 0.5;
        var idx: usize = 0;
        while (idx < 4) : (idx += 2) {
            const kw = tokens[idx];
            const off = parseSideVal(tokens[idx + 1], 0);
            if (std.mem.eql(u8, kw, "left")) x_val = off
            else if (std.mem.eql(u8, kw, "right")) x_val = width - off
            else if (std.mem.eql(u8, kw, "top")) y_val = off
            else if (std.mem.eql(u8, kw, "bottom")) y_val = height - off;
        }
        return .{ .x = x_val, .y = y_val, .z = 0 };
    }

    // 1-value syntax
    if (count == 1) {
        const tok = tokens[0];
        if (std.mem.eql(u8, tok, "top") or std.mem.eql(u8, tok, "bottom")) {
            return .{ .x = width * 0.5, .y = parseSideVal(tok, height), .z = 0 };
        }
        return .{ .x = parseSideVal(tok, width), .y = height * 0.5, .z = 0 };
    }

    // 2-value syntax
    if (count == 2) {
        var first = tokens[0];
        var second = tokens[1];
        if (std.mem.eql(u8, first, "top") or std.mem.eql(u8, first, "bottom") or std.mem.eql(u8, second, "left") or std.mem.eql(u8, second, "right")) {
            const tmp = first;
            first = second;
            second = tmp;
        }
        return .{ .x = parseSideVal(first, width), .y = parseSideVal(second, height), .z = 0 };
    }

    // 3-value syntax: x y z
    var first = tokens[0];
    var second = tokens[1];
    if (std.mem.eql(u8, first, "top") or std.mem.eql(u8, first, "bottom") or std.mem.eql(u8, second, "left") or std.mem.eql(u8, second, "right")) {
        const tmp = first;
        first = second;
        second = tmp;
    }
    const z_val = parseSideVal(tokens[2], 0);
    return .{ .x = parseSideVal(first, width), .y = parseSideVal(second, height), .z = z_val };
}

pub fn parseTransformOrigin(css: []const u8, width: f32, height: f32) Point {
    const o3 = parseTransformOrigin3D(css, width, height);
    return .{ .x = o3.x, .y = o3.y };
}

/// Parses perspective-origin (1 or 2 values: keywords or lengths/percentages).
pub fn parsePerspectiveOrigin(css: []const u8, width: f32, height: f32) Point {
    const o3 = parseTransformOrigin3D(css, width, height);
    return .{ .x = o3.x, .y = o3.y };
}

fn sizedLength(str: []const u8, size: f32) !f32 {
    const input = std.mem.trim(u8, str, " \t\r\n");
    if (std.fmt.parseFloat(f32, input)) |v| return v else |_| {}
    return switch (try @import("sizing.zig").resolve(input, .{ .percentage = size })) {
        .length => |v| v,
        else => error.InvalidTransformArgs,
    };
}
