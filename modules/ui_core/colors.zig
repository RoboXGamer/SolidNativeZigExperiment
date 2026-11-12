//! Context-free CSS Color 4 parsing, converted to the renderer's 8-bit sRGB.
//! Syntax and conversion constants: https://www.w3.org/TR/css-color-4/.
//! Out-of-gamut channels are clipped. Relative colors, var(), system
//! colors, and currentColor require style context and deliberately return null.
const std = @import("std");
const ws = " \t\r\n\x0c";
const Vec = [3]f64;
const Mat = [3]Vec;

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn suffix(a: []const u8, b: []const u8) bool {
    return a.len >= b.len and eq(a[a.len - b.len ..], b);
}

/// CSS number token, excluding non-CSS floats such as NaN, inf and hex floats.
pub fn number(s: []const u8) ?f64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    if (s[i] == '+' or s[i] == '-') i += 1;
    var digits: usize = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) digits += 1;
    if (i < s.len and s[i] == '.') {
        i += 1;
        const start = i;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) digits += 1;
        if (i == start) return null;
    }
    if (digits == 0) return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        const start = i;
        while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {}
        if (i == start) return null;
    }
    if (i != s.len) return null;
    const value = std.fmt.parseFloat(f64, s) catch return null;
    return if (std.math.isFinite(value)) value else null;
}

/// Percentages are scaled so that 100% equals percentage_scale.
fn component(s: []const u8, percentage_scale: f64, allow_none: bool) ?f64 {
    if (allow_none and eq(s, "none")) return 0;
    if (suffix(s, "%")) return (number(s[0 .. s.len - 1]) orelse return null) * percentage_scale / 100;
    if (std.mem.indexOfScalar(u8, s, '(') != null) {
        const value = (@import("sizing.zig").resolveNumber(s, .{ .percentage = @floatCast(percentage_scale) }) catch return null) orelse return null;
        return if (std.math.isNan(value)) 0 else value;
    }
    return number(s);
}

pub fn angle(s: []const u8, allow_number: bool) ?f64 {
    if (suffix(s, "grad")) return (number(s[0 .. s.len - 4]) orelse return null) * 0.9;
    if (suffix(s, "deg")) return number(s[0 .. s.len - 3]);
    if (suffix(s, "rad")) return (number(s[0 .. s.len - 3]) orelse return null) * 180 / std.math.pi;
    if (suffix(s, "turn")) return (number(s[0 .. s.len - 4]) orelse return null) * 360;
    if (std.mem.indexOfScalar(u8, s, '(') != null) {
        const q = @import("sizing.zig").resolveValue(s, .{}) catch return null;
        if (q.dimension != .angle and !(allow_number and q.dimension == .number)) return null;
        return q.value orelse return null;
    }
    if (allow_number) return number(s);
    return null;
}

const Arguments = struct {
    channels: [3][]const u8,
    alpha: ?[]const u8 = null,
    legacy: bool = false,
};

fn topLevel(input: []const u8, needle: u8) bool {
    var depth: usize = 0;
    for (input) |c| {
        if (c == '(') depth += 1 else if (c == ')') {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and c == needle) return true;
    }
    return false;
}
fn arguments(body: []const u8, allow_legacy: bool) ?Arguments {
    var result: Arguments = undefined;
    result.alpha = null;
    result.legacy = topLevel(body, ',');
    if (result.legacy) {
        if (!allow_legacy or topLevel(body, '/')) return null;
        var it = @import("css_syntax.zig").Split{ .input = body, .separator = ',' };
        for (&result.channels) |*c| {
            c.* = std.mem.trim(u8, it.next() orelse return null, ws);
            if (c.len == 0 or eq(c.*, "none")) return null;
        }
        if (it.next()) |a| {
            const trimmed = std.mem.trim(u8, a, ws);
            if (trimmed.len == 0 or eq(trimmed, "none")) return null;
            result.alpha = trimmed;
        }
        if (it.next() != null) return null;
    } else {
        var halves = @import("css_syntax.zig").Split{ .input = body, .separator = '/' };
        var it = @import("css_syntax.zig").Tokens{ .input = halves.next() orelse return null, .separators = ws };
        for (&result.channels) |*c| c.* = it.next() orelse return null;
        if (it.next() != null) return null;
        if (halves.next()) |a| {
            const trimmed = std.mem.trim(u8, a, ws);
            if (trimmed.len == 0) return null;
            result.alpha = trimmed;
        }
        if (halves.next() != null) return null;
    }
    return result;
}

fn pack(rgb: Vec, alpha: f64) ?[4]u8 {
    var result: [4]u8 = undefined;
    for (rgb, 0..) |v, i| {
        if (std.math.isNan(v)) return null;
        result[i] = @intFromFloat(@round(std.math.clamp(v, 0, 1) * 255));
    }
    result[3] = @intFromFloat(@round(std.math.clamp(alpha, 0, 1) * 255));
    return result;
}

fn multiply(m: Mat, v: Vec) Vec {
    var out: Vec = undefined;
    for (m, 0..) |row, i| out[i] = row[0] * v[0] + row[1] * v[1] + row[2] * v[2];
    return out;
}

fn signedPow(v: f64, exponent: f64) f64 {
    return std.math.copysign(std.math.pow(f64, @abs(v), exponent), v);
}

fn linearize(v: f64) f64 {
    return if (@abs(v) <= 0.04045) v / 12.92 else std.math.copysign(std.math.pow(f64, (@abs(v) + 0.055) / 1.055, 2.4), v);
}

fn encode(v: f64) f64 {
    return if (@abs(v) <= 0.0031308) 12.92 * v else 1.055 * signedPow(v, 1 / 2.4) - std.math.copysign(@as(f64, 0.055), v);
}

fn encoded(v: Vec) Vec {
    return .{ encode(v[0]), encode(v[1]), encode(v[2]) };
}

const xyz_to_srgb: Mat = .{
    .{ 3.2409699419045226, -1.537383177570094, -0.4986107602930034 },
    .{ -0.9692436362808796, 1.8759675015077202, 0.04155505740717559 },
    .{ 0.05563007969699366, -0.20397695888897652, 1.0569715142428786 },
};
const d50_to_d65: Mat = .{
    .{ 0.955473421488075, -0.02309845494876471, 0.06325924320057072 },
    .{ -0.0283697093338637, 1.0099953980813041, 0.021041441191917323 },
    .{ 0.012314014864481998, -0.020507649298898964, 1.330365926242124 },
};

fn xyzToRgb(xyz: Vec, d50: bool) Vec {
    return encoded(multiply(xyz_to_srgb, if (d50) multiply(d50_to_d65, xyz) else xyz));
}

fn hueRgb(hue: f64, saturation: f64, lightness: f64) Vec {
    const h = @mod(hue, 360) / 30;
    const a = saturation * @min(lightness, 1 - lightness);
    var result: Vec = undefined;
    for ([_]f64{ 0, 8, 4 }, 0..) |offset, i| {
        const k = @mod(h + offset, 12);
        result[i] = lightness - a * @max(-1, @min(@min(k - 3, 9 - k), 1));
    }
    return result;
}

fn labToRgb(lab: Vec, ok: bool) Vec {
    if (ok) {
        const l = lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2];
        const m = lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2];
        const s = lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2];
        return encoded(multiply(.{
            .{ 4.0767416621, -3.3077115913, 0.2309699292 },
            .{ -1.2684380046, 2.6097574011, -0.3413193965 },
            .{ -0.0041960863, -0.7034186147, 1.7076147010 },
        }, .{ l * l * l, m * m * m, s * s * s }));
    }
    const fy = (lab[0] + 16) / 116;
    const f = Vec{ fy + lab[1] / 500, fy, fy - lab[2] / 200 };
    const white = Vec{ 0.9642956764295677, 1, 0.8251046025104601 };
    var xyz: Vec = undefined;
    for (f, 0..) |v, i| xyz[i] = white[i] * (if (v > 6.0 / 29.0) v * v * v else (116 * v - 16) / (24389.0 / 27.0));
    return xyzToRgb(xyz, true);
}

fn explicitSpace(space: []const u8, input: Vec) ?Vec {
    if (eq(space, "srgb")) return input;
    if (eq(space, "srgb-linear")) return encoded(input);
    if (eq(space, "xyz") or eq(space, "xyz-d65")) return xyzToRgb(input, false);
    if (eq(space, "xyz-d50")) return xyzToRgb(input, true);
    var v = input;
    var matrix: Mat = undefined;
    var d50 = false;
    if (eq(space, "display-p3") or eq(space, "display-p3-linear")) {
        if (eq(space, "display-p3")) for (&v) |*c| {
            c.* = linearize(c.*);
        };
        matrix = .{
            .{ 0.4865709486482162, 0.26566769316909306, 0.1982172852343625 },
            .{ 0.2289745640697488, 0.6917385218365064, 0.079286914093745 },
            .{ 0, 0.04511338185890264, 1.043944368900976 },
        };
    } else if (eq(space, "a98-rgb")) {
        for (&v) |*c| c.* = signedPow(c.*, 563.0 / 256.0);
        matrix = .{
            .{ 0.5766690429101305, 0.1855582379065463, 0.1882286462349947 },
            .{ 0.29734497525053605, 0.6273635662554661, 0.0752914584939979 },
            .{ 0.02703136138641234, 0.07068885253582723, 0.9913375368376388 },
        };
    } else if (eq(space, "prophoto-rgb")) {
        for (&v) |*c| c.* = if (@abs(c.*) <= 16.0 / 512.0) c.* / 16 else signedPow(c.*, 1.8);
        d50 = true;
        matrix = .{
            .{ 0.7977666449006423, 0.13518129740053308, 0.0313477341283922 },
            .{ 0.2880748288194013, 0.711835234241873, 0.00008993693872564 },
            .{ 0, 0, 0.8251046025104601 },
        };
    } else if (eq(space, "rec2020")) {
        const a: f64 = 1.09929682680944;
        const b: f64 = 0.018053968510807;
        for (&v) |*c| c.* = if (@abs(c.*) < b * 4.5) c.* / 4.5 else std.math.copysign(std.math.pow(f64, (@abs(c.*) + a - 1) / a, 1 / 0.45), c.*);
        matrix = .{
            .{ 0.6369580483012914, 0.14461690358620832, 0.1688809751641721 },
            .{ 0.2627002120112671, 0.6779980715188708, 0.05930171646986196 },
            .{ 0, 0.028072693049087428, 1.060985057710791 },
        };
    } else return null;
    return xyzToRgb(multiply(matrix, v), d50);
}

fn rgbToHsl(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const r = @as(f64, @floatFromInt(r_u8)) / 255.0;
    const g = @as(f64, @floatFromInt(g_u8)) / 255.0;
    const b = @as(f64, @floatFromInt(b_u8)) / 255.0;
    const max = @max(r, @max(g, b));
    const min = @min(r, @min(g, b));
    const delta = max - min;
    const l = (max + min) / 2.0;
    var h: f64 = 0;
    var s: f64 = 0;
    if (delta > 1e-6) {
        s = if (l > 0.5) delta / (2.0 - max - min) else delta / (max + min);
        if (max == r) {
            h = (g - b) / delta + (if (g < b) @as(f64, 6.0) else 0.0);
        } else if (max == g) {
            h = (b - r) / delta + 2.0;
        } else {
            h = (r - g) / delta + 4.0;
        }
        h *= 60.0;
    }
    return .{ h, s * 100.0, l * 100.0 };
}

fn rgbToHwb(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const hsl = rgbToHsl(r_u8, g_u8, b_u8);
    const r = @as(f64, @floatFromInt(r_u8)) / 255.0;
    const g = @as(f64, @floatFromInt(g_u8)) / 255.0;
    const b = @as(f64, @floatFromInt(b_u8)) / 255.0;
    const w = @min(r, @min(g, b)) * 100.0;
    const blk = (1.0 - @max(r, @max(g, b))) * 100.0;
    return .{ hsl[0], w, blk };
}

fn rgbToOklab(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const r = linearize(@as(f64, @floatFromInt(r_u8)) / 255.0);
    const g = linearize(@as(f64, @floatFromInt(g_u8)) / 255.0);
    const b = linearize(@as(f64, @floatFromInt(b_u8)) / 255.0);
    const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    const l_ = std.math.cbrt(l);
    const m_ = std.math.cbrt(m);
    const s_ = std.math.cbrt(s);
    return .{
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    };
}

fn rgbToOklch(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const lab = rgbToOklab(r_u8, g_u8, b_u8);
    const c = std.math.hypot(lab[1], lab[2]);
    var h = std.math.atan2(lab[2], lab[1]) * 180.0 / std.math.pi;
    if (h < 0) h += 360.0;
    return .{ lab[0], c, h };
}

fn labF(t: f64) f64 {
    return if (t > 216.0 / 24389.0) std.math.cbrt(t) else (24389.0 / 27.0 * t + 16.0) / 116.0;
}

fn rgbToLab(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const r = linearize(@as(f64, @floatFromInt(r_u8)) / 255.0);
    const g = linearize(@as(f64, @floatFromInt(g_u8)) / 255.0);
    const b = linearize(@as(f64, @floatFromInt(b_u8)) / 255.0);
    const x65 = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
    const y65 = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    const z65 = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
    const x50 = 1.0478112 * x65 + 0.0228866 * y65 - 0.0501270 * z65;
    const y50 = 0.0295424 * x65 + 0.9904844 * y65 - 0.0170491 * z65;
    const z50 = -0.0092345 * x65 + 0.0150436 * y65 + 0.7521316 * z65;
    const fx = labF(x50 / 0.96422);
    const fy = labF(y50 / 1.0);
    const fz = labF(z50 / 0.82521);
    return .{ 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz) };
}

fn rgbToLch(r_u8: u8, g_u8: u8, b_u8: u8) Vec {
    const lab = rgbToLab(r_u8, g_u8, b_u8);
    const c = std.math.hypot(lab[1], lab[2]);
    var h = std.math.atan2(lab[2], lab[1]) * 180.0 / std.math.pi;
    if (h < 0) h += 360.0;
    return .{ lab[0], c, h };
}

fn parseRelativeColor(name: []const u8, body: []const u8) ?[4]u8 {
    var i: usize = 4;
    while (i < body.len and std.ascii.isWhitespace(body[i])) : (i += 1) {}
    if (i >= body.len) return null;
    const origin_start = i;
    var paren_depth: usize = 0;
    while (i < body.len) : (i += 1) {
        if (body[i] == '(') {
            paren_depth += 1;
        } else if (body[i] == ')') {
            if (paren_depth > 0) paren_depth -= 1;
        } else if (paren_depth == 0 and std.ascii.isWhitespace(body[i])) {
            break;
        }
    }
    const origin_str = body[origin_start..i];
    const origin_rgba = parseColor(origin_str) orelse return null;
    var rest = std.mem.trim(u8, body[i..], ws);
    var space: []const u8 = "";
    if (eq(name, "color")) {
        const space_end = std.mem.indexOfAny(u8, rest, ws) orelse return null;
        space = rest[0..space_end];
        rest = std.mem.trim(u8, rest[space_end..], ws);
    }
    const rgb = eq(name, "rgb") or eq(name, "rgba");
    const hsl = eq(name, "hsl") or eq(name, "hsla");
    const hwb = eq(name, "hwb");
    const lab = eq(name, "lab") or eq(name, "lch") or eq(name, "oklab") or eq(name, "oklch");
    if (!rgb and !hsl and !hwb and !lab and !eq(name, "color")) return null;

    var halves = @import("css_syntax.zig").Split{ .input = rest, .separator = '/' };
    const channels_body = halves.next() orelse return null;
    const alpha_body = if (halves.next()) |a| std.mem.trim(u8, a, ws) else null;
    if (halves.next() != null) return null;

    var it = @import("css_syntax.zig").Tokens{ .input = channels_body, .separators = ws };
    var ch_tokens: [3][]const u8 = undefined;
    for (&ch_tokens) |*c| c.* = it.next() orelse return null;
    if (it.next() != null) return null;

    var n0: []const u8 = "r";
    var n1: []const u8 = "g";
    var n2: []const u8 = "b";
    var orig_c: Vec = undefined;
    const orig_alpha: f64 = @as(f64, @floatFromInt(origin_rgba[3])) / 255.0;

    if (rgb) {
        orig_c = .{ @floatFromInt(origin_rgba[0]), @floatFromInt(origin_rgba[1]), @floatFromInt(origin_rgba[2]) };
    } else if (hsl) {
        n0 = "h"; n1 = "s"; n2 = "l";
        orig_c = rgbToHsl(origin_rgba[0], origin_rgba[1], origin_rgba[2]);
    } else if (hwb) {
        n0 = "h"; n1 = "w"; n2 = "b";
        orig_c = rgbToHwb(origin_rgba[0], origin_rgba[1], origin_rgba[2]);
    } else if (lab) {
        const ok = eq(name, "oklab") or eq(name, "oklch");
        const polar = eq(name, "lch") or eq(name, "oklch");
        if (ok) {
            orig_c = if (polar) rgbToOklch(origin_rgba[0], origin_rgba[1], origin_rgba[2]) else rgbToOklab(origin_rgba[0], origin_rgba[1], origin_rgba[2]);
            if (polar) { n0 = "l"; n1 = "c"; n2 = "h"; } else { n0 = "l"; n1 = "a"; n2 = "b"; }
        } else {
            orig_c = if (polar) rgbToLch(origin_rgba[0], origin_rgba[1], origin_rgba[2]) else rgbToLab(origin_rgba[0], origin_rgba[1], origin_rgba[2]);
            if (polar) { n0 = "l"; n1 = "c"; n2 = "h"; } else { n0 = "l"; n1 = "a"; n2 = "b"; }
        }
    } else {
        orig_c = .{ @as(f64, @floatFromInt(origin_rgba[0])) / 255.0, @as(f64, @floatFromInt(origin_rgba[1])) / 255.0, @as(f64, @floatFromInt(origin_rgba[2])) / 255.0 };
    }

    const evalToken = struct {
        fn eval(tok: []const u8, name0: []const u8, name1: []const u8, name2: []const u8, c_vals: Vec, a_val: f64, pct_scale: f64) ?f64 {
            if (eq(tok, "none")) return 0;
            if (eq(tok, name0)) return c_vals[0];
            if (eq(tok, name1)) return c_vals[1];
            if (eq(tok, name2)) return c_vals[2];
            if (eq(tok, "alpha")) return a_val;
            if (suffix(tok, "%")) {
                const n = number(tok[0 .. tok.len - 1]) orelse return null;
                return n * pct_scale / 100.0;
            }
            if (std.mem.startsWith(u8, tok, "calc(") and std.mem.endsWith(u8, tok, ")")) {
                var buf: [256]u8 = undefined;
                var out_len: usize = 0;
                var p: usize = 0;
                while (p < tok.len) {
                    if (std.ascii.isAlphabetic(tok[p])) {
                        const id_start = p;
                        while (p < tok.len and std.ascii.isAlphanumeric(tok[p])) : (p += 1) {}
                        const id = tok[id_start..p];
                        var val: ?f64 = null;
                        if (eq(id, name0)) val = c_vals[0]
                        else if (eq(id, name1)) val = c_vals[1]
                        else if (eq(id, name2)) val = c_vals[2]
                        else if (eq(id, "alpha")) val = a_val;
                        if (val) |v| {
                            const formatted = std.fmt.bufPrint(buf[out_len..], "{d:.4}", .{v}) catch return null;
                            out_len += formatted.len;
                        } else {
                            if (out_len + id.len > buf.len) return null;
                            @memcpy(buf[out_len .. out_len + id.len], id);
                            out_len += id.len;
                        }
                    } else {
                        if (out_len >= buf.len) return null;
                        buf[out_len] = tok[p];
                        out_len += 1;
                        p += 1;
                    }
                }
                const resolved = (@import("sizing.zig").resolveNumber(buf[0..out_len], .{}) catch return null) orelse return null;
                return resolved;
            }
            return number(tok);
        }
    }.eval;

    var resolved_c: Vec = undefined;
    const scales: [3]f64 = if (rgb) .{ 255, 255, 255 } else if (hsl or hwb) .{ 360, 100, 100 } else if (lab) (if (eq(name, "oklab") or eq(name, "oklch")) .{ 1, 0.4, 360 } else .{ 100, 125, 360 }) else .{ 1, 1, 1 };
    for (ch_tokens, 0..) |tok, idx| {
        resolved_c[idx] = evalToken(tok, n0, n1, n2, orig_c, orig_alpha, scales[idx]) orelse return null;
    }

    const resolved_alpha = if (alpha_body) |ab| (evalToken(ab, n0, n1, n2, orig_c, orig_alpha, 1.0) orelse return null) else orig_alpha;

    if (rgb) {
        return pack(.{ resolved_c[0] / 255.0, resolved_c[1] / 255.0, resolved_c[2] / 255.0 }, resolved_alpha);
    }
    if (hsl) {
        const x = std.math.clamp(resolved_c[1] / 100.0, 0, 1);
        const y = std.math.clamp(resolved_c[2] / 100.0, 0, 1);
        return pack(hueRgb(resolved_c[0], x, y), resolved_alpha);
    }
    if (hwb) {
        const x = std.math.clamp(resolved_c[1] / 100.0, 0, 1);
        const y = std.math.clamp(resolved_c[2] / 100.0, 0, 1);
        if (x + y >= 1) return pack(.{ x / (x + y), x / (x + y), x / (x + y) }, resolved_alpha);
        var out = hueRgb(resolved_c[0], 1, 0.5);
        for (&out) |*v| v.* = v.* * (1 - x - y) + x;
        return pack(out, resolved_alpha);
    }
    if (lab) {
        const ok = eq(name, "oklab") or eq(name, "oklch");
        const polar = eq(name, "lch") or eq(name, "oklch");
        var l = resolved_c[0];
        var a = resolved_c[1];
        var b = resolved_c[2];
        if (polar) {
            const chroma = @max(0, a);
            const radians = @mod(b, 360) * std.math.pi / 180.0;
            a = chroma * @cos(radians);
            b = chroma * @sin(radians);
        }
        return pack(labToRgb(.{ l, a, b }, ok), resolved_alpha);
    }
    return pack(explicitSpace(space, resolved_c) orelse return null, resolved_alpha);
}

pub fn parseColor(input: []const u8) ?[4]u8 {
    const s = std.mem.trim(u8, input, ws);
    if (s.len == 0) return null;
    if (eq(s, "transparent")) return .{ 0, 0, 0, 0 };
    if (s[0] == '#') {
        const hex = s[1..];
        if (hex.len != 3 and hex.len != 4 and hex.len != 6 and hex.len != 8) return null;
        for (hex) |c| if (!std.ascii.isHex(c)) return null;
        var rgba: [4]u8 = .{ 0, 0, 0, 255 };
        const short = hex.len <= 4;
        const stride: usize = if (short) 1 else 2;
        for (0..hex.len / stride) |i| {
            const value = std.fmt.parseInt(u8, hex[i * stride ..][0..stride], 16) catch return null;
            rgba[i] = if (short) value * 17 else value;
        }
        return rgba;
    }
    if (std.mem.indexOfScalar(u8, s, '(')) |open| {
        if (s[s.len - 1] != ')') return null;
        const name = s[0..open];
        var body = std.mem.trim(u8, s[open + 1 .. s.len - 1], ws);
        if (std.ascii.startsWithIgnoreCase(body, "from ") or std.ascii.startsWithIgnoreCase(body, "from\t")) {
            return parseRelativeColor(name, body);
        }
        var space: []const u8 = "";
        if (eq(name, "color")) {
            const end = std.mem.indexOfAny(u8, body, ws) orelse return null;
            space = body[0..end];
            body = std.mem.trim(u8, body[end..], ws);
        }
        const rgb = eq(name, "rgb") or eq(name, "rgba");
        const hsl = eq(name, "hsl") or eq(name, "hsla");
        const hwb = eq(name, "hwb");
        const lab = eq(name, "lab") or eq(name, "lch") or eq(name, "oklab") or eq(name, "oklch");
        if (!rgb and !hsl and !hwb and !lab and !eq(name, "color")) return null;
        const args = arguments(body, rgb or hsl) orelse return null;
        const alpha = if (args.alpha) |a| component(a, 1, !args.legacy) orelse return null else 1;
        const c = args.channels;
        if (rgb) {
            if (args.legacy and (suffix(c[0], "%") != suffix(c[1], "%") or suffix(c[0], "%") != suffix(c[2], "%"))) return null;
            return pack(.{
                (component(c[0], 255, !args.legacy) orelse return null) / 255,
                (component(c[1], 255, !args.legacy) orelse return null) / 255,
                (component(c[2], 255, !args.legacy) orelse return null) / 255,
            }, alpha);
        }
        if (hsl or hwb) {
            const hue = if (!args.legacy and eq(c[0], "none")) 0 else angle(c[0], true) orelse return null;
            if (args.legacy and (!suffix(c[1], "%") or !suffix(c[2], "%"))) return null;
            // Number S/L/W/B values use a 0..100 scale, like percentages.
            const x = std.math.clamp((component(c[1], 100, !args.legacy) orelse return null) / 100, 0, 1);
            const y = std.math.clamp((component(c[2], 100, !args.legacy) orelse return null) / 100, 0, 1);
            if (hsl) return pack(hueRgb(hue, x, y), alpha);
            if (x + y >= 1) return pack(.{ x / (x + y), x / (x + y), x / (x + y) }, alpha);
            var out = hueRgb(hue, 1, 0.5);
            for (&out) |*v| v.* = v.* * (1 - x - y) + x;
            return pack(out, alpha);
        }
        if (lab) {
            const ok = eq(name, "oklab") or eq(name, "oklch");
            const polar = eq(name, "lch") or eq(name, "oklch");
            const l_scale: f64 = if (ok) 1 else 100;
            const a_scale: f64 = if (ok) 0.4 else if (polar) 150 else 125;
            const l = std.math.clamp(component(c[0], l_scale, true) orelse return null, 0, l_scale);
            var a = component(c[1], a_scale, true) orelse return null;
            var b = if (polar) (if (eq(c[2], "none")) 0 else angle(c[2], true) orelse return null) else component(c[2], a_scale, true) orelse return null;
            if (polar) {
                const chroma = @max(0, a);
                const radians = @mod(b, 360) * std.math.pi / 180;
                a = chroma * @cos(radians);
                b = chroma * @sin(radians);
            }
            return pack(labToRgb(.{ l, a, b }, ok), alpha);
        }
        return pack(explicitSpace(space, .{
            component(c[0], 1, true) orelse return null,
            component(c[1], 1, true) orelse return null,
            component(c[2], 1, true) orelse return null,
        }) orelse return null, alpha);
    }
    // Keyword matching is ASCII case-insensitive, without heap allocation.
    if (s.len > 20) return null;
    var lowercase: [20]u8 = undefined;
    for (s, 0..) |c, i| lowercase[i] = std.ascii.toLower(c);
    const value = named_colors.get(lowercase[0..s.len]) orelse return null;
    return .{ @intCast(value >> 16), @intCast((value >> 8) & 255), @intCast(value & 255), 255 };
}

// Named-color data: https://github.com/colorjs/color-name
// The MIT License (MIT)
// Copyright (c) 2015 Dmitry Ivanov
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
const named_colors = std.StaticStringMap(u32).initComptime(.{
    .{ "aliceblue", 0xf0f8ff },
    .{ "antiquewhite", 0xfaebd7 },
    .{ "aqua", 0x00ffff },
    .{ "aquamarine", 0x7fffd4 },
    .{ "azure", 0xf0ffff },
    .{ "beige", 0xf5f5dc },
    .{ "bisque", 0xffe4c4 },
    .{ "black", 0x000000 },
    .{ "blanchedalmond", 0xffebcd },
    .{ "blue", 0x0000ff },
    .{ "blueviolet", 0x8a2be2 },
    .{ "brown", 0xa52a2a },
    .{ "burlywood", 0xdeb887 },
    .{ "cadetblue", 0x5f9ea0 },
    .{ "chartreuse", 0x7fff00 },
    .{ "chocolate", 0xd2691e },
    .{ "coral", 0xff7f50 },
    .{ "cornflowerblue", 0x6495ed },
    .{ "cornsilk", 0xfff8dc },
    .{ "crimson", 0xdc143c },
    .{ "cyan", 0x00ffff },
    .{ "darkblue", 0x00008b },
    .{ "darkcyan", 0x008b8b },
    .{ "darkgoldenrod", 0xb8860b },
    .{ "darkgray", 0xa9a9a9 },
    .{ "darkgreen", 0x006400 },
    .{ "darkgrey", 0xa9a9a9 },
    .{ "darkkhaki", 0xbdb76b },
    .{ "darkmagenta", 0x8b008b },
    .{ "darkolivegreen", 0x556b2f },
    .{ "darkorange", 0xff8c00 },
    .{ "darkorchid", 0x9932cc },
    .{ "darkred", 0x8b0000 },
    .{ "darksalmon", 0xe9967a },
    .{ "darkseagreen", 0x8fbc8f },
    .{ "darkslateblue", 0x483d8b },
    .{ "darkslategray", 0x2f4f4f },
    .{ "darkslategrey", 0x2f4f4f },
    .{ "darkturquoise", 0x00ced1 },
    .{ "darkviolet", 0x9400d3 },
    .{ "deeppink", 0xff1493 },
    .{ "deepskyblue", 0x00bfff },
    .{ "dimgray", 0x696969 },
    .{ "dimgrey", 0x696969 },
    .{ "dodgerblue", 0x1e90ff },
    .{ "firebrick", 0xb22222 },
    .{ "floralwhite", 0xfffaf0 },
    .{ "forestgreen", 0x228b22 },
    .{ "fuchsia", 0xff00ff },
    .{ "gainsboro", 0xdcdcdc },
    .{ "ghostwhite", 0xf8f8ff },
    .{ "gold", 0xffd700 },
    .{ "goldenrod", 0xdaa520 },
    .{ "gray", 0x808080 },
    .{ "green", 0x008000 },
    .{ "greenyellow", 0xadff2f },
    .{ "grey", 0x808080 },
    .{ "honeydew", 0xf0fff0 },
    .{ "hotpink", 0xff69b4 },
    .{ "indianred", 0xcd5c5c },
    .{ "indigo", 0x4b0082 },
    .{ "ivory", 0xfffff0 },
    .{ "khaki", 0xf0e68c },
    .{ "lavender", 0xe6e6fa },
    .{ "lavenderblush", 0xfff0f5 },
    .{ "lawngreen", 0x7cfc00 },
    .{ "lemonchiffon", 0xfffacd },
    .{ "lightblue", 0xadd8e6 },
    .{ "lightcoral", 0xf08080 },
    .{ "lightcyan", 0xe0ffff },
    .{ "lightgoldenrodyellow", 0xfafad2 },
    .{ "lightgray", 0xd3d3d3 },
    .{ "lightgreen", 0x90ee90 },
    .{ "lightgrey", 0xd3d3d3 },
    .{ "lightpink", 0xffb6c1 },
    .{ "lightsalmon", 0xffa07a },
    .{ "lightseagreen", 0x20b2aa },
    .{ "lightskyblue", 0x87cefa },
    .{ "lightslategray", 0x778899 },
    .{ "lightslategrey", 0x778899 },
    .{ "lightsteelblue", 0xb0c4de },
    .{ "lightyellow", 0xffffe0 },
    .{ "lime", 0x00ff00 },
    .{ "limegreen", 0x32cd32 },
    .{ "linen", 0xfaf0e6 },
    .{ "magenta", 0xff00ff },
    .{ "maroon", 0x800000 },
    .{ "mediumaquamarine", 0x66cdaa },
    .{ "mediumblue", 0x0000cd },
    .{ "mediumorchid", 0xba55d3 },
    .{ "mediumpurple", 0x9370db },
    .{ "mediumseagreen", 0x3cb371 },
    .{ "mediumslateblue", 0x7b68ee },
    .{ "mediumspringgreen", 0x00fa9a },
    .{ "mediumturquoise", 0x48d1cc },
    .{ "mediumvioletred", 0xc71585 },
    .{ "midnightblue", 0x191970 },
    .{ "mintcream", 0xf5fffa },
    .{ "mistyrose", 0xffe4e1 },
    .{ "moccasin", 0xffe4b5 },
    .{ "navajowhite", 0xffdead },
    .{ "navy", 0x000080 },
    .{ "oldlace", 0xfdf5e6 },
    .{ "olive", 0x808000 },
    .{ "olivedrab", 0x6b8e23 },
    .{ "orange", 0xffa500 },
    .{ "orangered", 0xff4500 },
    .{ "orchid", 0xda70d6 },
    .{ "palegoldenrod", 0xeee8aa },
    .{ "palegreen", 0x98fb98 },
    .{ "paleturquoise", 0xafeeee },
    .{ "palevioletred", 0xdb7093 },
    .{ "papayawhip", 0xffefd5 },
    .{ "peachpuff", 0xffdab9 },
    .{ "peru", 0xcd853f },
    .{ "pink", 0xffc0cb },
    .{ "plum", 0xdda0dd },
    .{ "powderblue", 0xb0e0e6 },
    .{ "purple", 0x800080 },
    .{ "rebeccapurple", 0x663399 },
    .{ "red", 0xff0000 },
    .{ "rosybrown", 0xbc8f8f },
    .{ "royalblue", 0x4169e1 },
    .{ "saddlebrown", 0x8b4513 },
    .{ "salmon", 0xfa8072 },
    .{ "sandybrown", 0xf4a460 },
    .{ "seagreen", 0x2e8b57 },
    .{ "seashell", 0xfff5ee },
    .{ "sienna", 0xa0522d },
    .{ "silver", 0xc0c0c0 },
    .{ "skyblue", 0x87ceeb },
    .{ "slateblue", 0x6a5acd },
    .{ "slategray", 0x708090 },
    .{ "slategrey", 0x708090 },
    .{ "snow", 0xfffafa },
    .{ "springgreen", 0x00ff7f },
    .{ "steelblue", 0x4682b4 },
    .{ "tan", 0xd2b48c },
    .{ "teal", 0x008080 },
    .{ "thistle", 0xd8bfd8 },
    .{ "tomato", 0xff6347 },
    .{ "turquoise", 0x40e0d0 },
    .{ "violet", 0xee82ee },
    .{ "wheat", 0xf5deb3 },
    .{ "white", 0xffffff },
    .{ "whitesmoke", 0xf5f5f5 },
    .{ "yellow", 0xffff00 },
    .{ "yellowgreen", 0x9acd32 },
});
