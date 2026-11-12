//! Cached paint textures and GPU composition. All visual parts share the same
//! world transform; a stacking context's opacity is applied after its subtree.
const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui_core");
const mask_source = @embedFile("shaders/clip.fs");
const composite_source = @embedFile("shaders/composite.fs");
const Layer = struct { texture: rl.Texture2D, x: f32 = 0, y: f32 = 0, inset: bool = false };
const Cached = struct { hash: u64, layers: std.ArrayList(Layer) = .empty, background: ?rl.Texture2D = null, border: ?rl.Texture2D = null, outline: ?Layer = null };
pub const DrawFn = *const fn (*anyopaque, *ui.Scene, ui.Item, std.mem.Allocator) anyerror!void;
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    cache: std.AutoHashMap(u32, Cached),
    targets: std.ArrayList(rl.RenderTexture2D) = .empty,
    content_target: ?rl.RenderTexture2D = null,
    mask_shader: rl.Shader,
    composite_shader: rl.Shader,
    width: i32 = 0,
    height: i32 = 0,

    pub fn init(a: std.mem.Allocator) !Renderer {
        const shader = try rl.loadShaderFromMemory(null, mask_source);
        errdefer rl.unloadShader(shader);
        return .{ .allocator = a, .cache = std.AutoHashMap(u32, Cached).init(a), .mask_shader = shader, .composite_shader = try rl.loadShaderFromMemory(null, composite_source) };
    }
    fn freeCached(self: *Renderer, c: *Cached) void {
        for (c.layers.items) |layer| rl.unloadTexture(layer.texture);
        c.layers.deinit(self.allocator);
        if (c.background) |t| rl.unloadTexture(t);
        if (c.border) |t| rl.unloadTexture(t);
        if (c.outline) |layer| rl.unloadTexture(layer.texture);
    }
    pub fn deinit(self: *Renderer) void {
        var it = self.cache.valueIterator();
        while (it.next()) |c| self.freeCached(c);
        self.cache.deinit();
        for (self.targets.items) |t| rl.unloadRenderTexture(t);
        self.targets.deinit(self.allocator);
        if (self.content_target) |t| rl.unloadRenderTexture(t);
        rl.unloadShader(self.mask_shader);
        rl.unloadShader(self.composite_shader);
    }
    fn target(self: *Renderer, index: usize) !rl.RenderTexture2D {
        while (self.targets.items.len <= index) {
            const texture = try rl.loadRenderTexture(self.width, self.height);
            self.targets.append(self.allocator, texture) catch |err| {
                rl.unloadRenderTexture(texture);
                return err;
            };
        }
        return self.targets.items[index];
    }
    fn clear(t: rl.RenderTexture2D, c: rl.Color) void {
        rl.beginTextureMode(t);
        rl.clearBackground(c);
        rl.endTextureMode();
    }
    fn upload(b: ui.paint.Bitmap) !rl.Texture2D {
        const image = rl.Image{ .data = @ptrCast(b.pixels.ptr), .width = @intCast(b.width), .height = @intCast(b.height), .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
        return rl.loadTextureFromImage(image);
    }
    fn cached(self: *Renderer, item: ui.Item, a: std.mem.Allocator) !*Cached {
        const n = item.node;
        const width: usize = @intFromFloat(@max(1, @ceil(item.bounds.width)));
        const height: usize = @intFromFloat(@max(1, @ceil(item.bounds.height)));
        const data = try std.json.Stringify.valueAlloc(a, .{ n.style, width, height }, .{});
        defer a.free(data);
        const hash = std.hash.Wyhash.hash(0, data);
        const entry = try self.cache.getOrPut(n.id);
        if (entry.found_existing and entry.value_ptr.hash == hash) return entry.value_ptr;
        // Build off-cache, so an allocation/upload failure leaves no leaked or
        // half-initialized texture entry.
        var result = Cached{ .hash = hash };
        errdefer {
            self.freeCached(&result);
            if (!entry.found_existing) _ = self.cache.remove(n.id);
        }
        const radius = ui.paint.resolvedRadii(n, @floatFromInt(width), @floatFromInt(height));
        var fill = ui.gradient.parseColor(n.style.backgroundColor) orelse .{ 0, 0, 0, 0 };
        if (n.style.backgroundColor.len == 0 and (std.mem.eql(u8, n.type, "button") or std.mem.eql(u8, n.type, "input") or std.mem.eql(u8, n.type, "select"))) fill = .{ 80, 80, 80, 255 };
        if (n.style.backgroundColor.len == 0 and std.mem.eql(u8, n.type, "option")) fill = .{ 40, 40, 40, 255 };
        const gradient = try ui.gradient.parseGradient(a, n.style.backgroundGradient);
        defer if (gradient) |g| a.free(g.stops);
        if (fill[3] > 0 or gradient != null) {
            const bitmap = try ui.paint.backgroundElliptical(a, width, height, radius, fill, gradient);
            defer a.free(bitmap.pixels);
            result.background = try upload(bitmap);
        }
        const shadows = try ui.paint.shadows(a, n.style.boxShadow);
        defer a.free(shadows);
        var i = shadows.len;
        while (i > 0) {
            i -= 1;
            const padding_box = n.paddingBox(.{ .width = @floatFromInt(width), .height = @floatFromInt(height) });
            const inset = shadows[i].inset;
            const shadow_width: usize = if (inset) @intFromFloat(@max(0, @ceil(padding_box.width))) else width;
            const shadow_height: usize = if (inset) @intFromFloat(@max(0, @ceil(padding_box.height))) else height;
            if (shadow_width == 0 or shadow_height == 0) continue;
            const shadow_radius = if (inset) ui.paint.paddingRadii(n, .{ .width = @floatFromInt(width), .height = @floatFromInt(height) }) else radius;
            const bitmap = try ui.paint.shadowBitmapElliptical(a, shadow_width, shadow_height, shadow_radius, shadows[i]);
            defer a.free(bitmap.pixels);
            const texture = try upload(bitmap);
            result.layers.append(self.allocator, .{ .texture = texture, .x = bitmap.x + (if (inset) padding_box.x else 0), .y = bitmap.y + (if (inset) padding_box.y else 0), .inset = inset }) catch |err| {
                rl.unloadTexture(texture);
                return err;
            };
        }
        const bw = n.border();
        if (bw.top > 0 or bw.right > 0 or bw.bottom > 0 or bw.left > 0) {
            const bitmap = try ui.paint.borderBitmap(a, width, height, n);
            defer a.free(bitmap.pixels);
            result.border = try upload(bitmap);
        }
        if (ui.paint.outline(n)) |outline| {
            const bitmap = try ui.paint.outlineBitmap(a, width, height, n, outline);
            defer a.free(bitmap.pixels);
            result.outline = .{ .texture = try upload(bitmap), .x = bitmap.x, .y = bitmap.y };
        }
        if (entry.found_existing) self.freeCached(entry.value_ptr);
        entry.value_ptr.* = result;
        return entry.value_ptr;
    }
    fn affine(m: ui.transform.Matrix2D) rl.Matrix {
        return .{ .m0 = m.a, .m1 = m.b, .m2 = 0, .m3 = 0, .m4 = m.c, .m5 = m.d, .m6 = 0, .m7 = 0, .m8 = 0, .m9 = 0, .m10 = 1, .m11 = 0, .m12 = m.tx, .m13 = m.ty, .m14 = 0, .m15 = 1 };
    }
    fn matrix4(m: ui.transform.Matrix4x4) rl.Matrix {
        return .{
            .m0 = m.m[0], .m1 = m.m[1], .m2 = m.m[2], .m3 = m.m[3],
            .m4 = m.m[4], .m5 = m.m[5], .m6 = m.m[6], .m7 = m.m[7],
            .m8 = m.m[8], .m9 = m.m[9], .m10 = m.m[10], .m11 = m.m[11],
            .m12 = m.m[12], .m13 = m.m[13], .m14 = m.m[14], .m15 = m.m[15],
        };
    }
    fn textureAt(texture: rl.Texture2D, x: f32, y: f32) void {
        rl.drawTextureV(texture, .{ .x = x, .y = y }, .white);
    }
    fn full(self: *Renderer, texture: rl.Texture2D) void {
        rl.drawTexturePro(texture, .{ .x = 0, .y = 0, .width = @floatFromInt(self.width), .height = -@as(f32, @floatFromInt(self.height)) }, .{ .x = 0, .y = 0, .width = @floatFromInt(self.width), .height = @floatFromInt(self.height) }, .{ .x = 0, .y = 0 }, 0, .white);
    }
    fn uniform(shader: rl.Shader, name: [:0]const u8, value: *const anyopaque, kind: rl.ShaderUniformDataType) void {
        rl.setShaderValue(shader, rl.getShaderLocation(shader, name), value, kind);
    }
    fn mask(self: *Renderer, scene: *ui.Scene, item: ui.Item) !rl.Texture2D {
        var current = try self.target(0);
        var next = try self.target(1);
        clear(current, .white);
        var parent = item.parent_id;
        while (parent) |pid| {
            const p = scene.find(pid) orelse break;
            parent = p.parent_id;
            if ((!p.node.clipsX() and !p.node.clipsY()) or !scene.clipApplies(item, p)) continue;
            const inv = scene.worldTransform4x4(p).inverse() orelse return current.texture;
            const box = p.node.paddingBox(p.bounds);
            const rect = [4]f32{ box.x, box.y, box.width, box.height };
            const radius = ui.paint.paddingRadii(p.node, p.bounds);
            const axes = [2]f32{ if (p.node.clipsX()) 1 else 0, if (p.node.clipsY()) 1 else 0 };
            const resolution = [2]f32{ @floatFromInt(self.width), @floatFromInt(self.height) };
            rl.beginTextureMode(next);
            rl.clearBackground(.blank);
            rl.beginShaderMode(self.mask_shader);
            uniform(self.mask_shader, "box", &rect, .vec4);
            uniform(self.mask_shader, "radiiX", &radius.x, .vec4);
            uniform(self.mask_shader, "radiiY", &radius.y, .vec4);
            uniform(self.mask_shader, "axes", &axes, .vec2);
            uniform(self.mask_shader, "resolution", &resolution, .vec2);
            rl.setShaderValueMatrix(self.mask_shader, rl.getShaderLocation(self.mask_shader, "inverseWorld"), matrix4(inv));
            self.full(current.texture);
            rl.endShaderMode();
            rl.endTextureMode();
            const swap = current;
            current = next;
            next = swap;
        }
        return current.texture;
    }
    fn contentMask(self: *Renderer, scene: *ui.Scene, item: ui.Item) !rl.Texture2D {
        const current = try self.target(0);
        const next = try self.target(1);
        clear(current, .white);
        const input = std.mem.eql(u8, item.node.type, "input");
        const clips_x = item.node.clipsX() or input;
        const clips_y = item.node.clipsY() or input;
        if (!clips_x and !clips_y) return current.texture;
        const inv = scene.worldTransform4x4(item).inverse() orelse {
            clear(current, .blank);
            return current.texture;
        };
        const box = item.node.paddingBox(item.bounds);
        const rect = [4]f32{ box.x, box.y, box.width, box.height };
        const radius = ui.paint.paddingRadii(item.node, item.bounds);
        const axes = [2]f32{ if (clips_x) 1 else 0, if (clips_y) 1 else 0 };
        const resolution = [2]f32{ @floatFromInt(self.width), @floatFromInt(self.height) };
        clear(next, .blank);
        rl.beginTextureMode(next);
        rl.beginShaderMode(self.mask_shader);
        uniform(self.mask_shader, "box", &rect, .vec4);
        uniform(self.mask_shader, "radiiX", &radius.x, .vec4);
        uniform(self.mask_shader, "radiiY", &radius.y, .vec4);
        uniform(self.mask_shader, "axes", &axes, .vec2);
        uniform(self.mask_shader, "resolution", &resolution, .vec2);
        rl.setShaderValueMatrix(self.mask_shader, rl.getShaderLocation(self.mask_shader, "inverseWorld"), matrix4(inv));
        self.full(current.texture);
        rl.endShaderMode();
        rl.endTextureMode();
        return next.texture;
    }
    fn composite(self: *Renderer, source: rl.Texture2D, dest: rl.RenderTexture2D, mask_texture: rl.Texture2D, opacity: f32) void {
        rl.beginTextureMode(dest);
        rl.beginBlendMode(.alpha_premultiply);
        rl.beginShaderMode(self.composite_shader);
        rl.setShaderValueTexture(self.composite_shader, rl.getShaderLocation(self.composite_shader, "maskTexture"), mask_texture);
        uniform(self.composite_shader, "opacity", &opacity, .float);
        self.full(source);
        rl.endShaderMode();
        rl.endBlendMode();
        rl.endTextureMode();
    }
    fn drawItem(self: *Renderer, scene: *ui.Scene, item: ui.Item, dest: rl.RenderTexture2D, ctx: *anyopaque, draw: DrawFn, a: std.mem.Allocator) !void {
        if (item.bounds.width <= 0 or item.bounds.height <= 0 or !ui.interaction.isVisible(item.node)) return;
        const w4 = scene.worldTransform4x4(item);
        if (std.ascii.eqlIgnoreCase(item.node.style.backfaceVisibility, "hidden") and w4.isBackface()) return;
        const layer = try self.target(2);
        const c = try self.cached(item, a);
        clear(layer, .blank);
        rl.beginTextureMode(layer);
        rl.gl.rlPushMatrix();
        const matrix = w4.m;
        rl.gl.rlMultMatrixf(&matrix);
        for (c.layers.items) |effect| if (!effect.inset) textureAt(effect.texture, item.bounds.x + effect.x, item.bounds.y + effect.y);
        if (c.background) |texture| textureAt(texture, item.bounds.x, item.bounds.y);
        for (c.layers.items) |effect| if (effect.inset) textureAt(effect.texture, item.bounds.x + effect.x, item.bounds.y + effect.y);
        if (c.border) |texture| textureAt(texture, item.bounds.x, item.bounds.y);
        rl.gl.rlPopMatrix();
        rl.endTextureMode();
        if (self.content_target == null) self.content_target = try rl.loadRenderTexture(self.width, self.height);
        const content = self.content_target.?;
        clear(content, .blank);
        rl.beginTextureMode(content);
        rl.gl.rlPushMatrix();
        rl.gl.rlMultMatrixf(&matrix);
        draw(ctx, scene, item, a) catch |err| {
            rl.gl.rlPopMatrix();
            rl.endTextureMode();
            return err;
        };
        rl.gl.rlPopMatrix();
        rl.endTextureMode();
        self.composite(content.texture, layer, try self.contentMask(scene, item), 1);
        if (c.outline) |outline| {
            rl.beginTextureMode(layer);
            rl.gl.rlPushMatrix();
            rl.gl.rlMultMatrixf(&matrix);
            textureAt(outline.texture, item.bounds.x + outline.x, item.bounds.y + outline.y);
            rl.gl.rlPopMatrix();
            rl.endTextureMode();
        }
        self.composite(layer.texture, dest, try self.mask(scene, item), 1);
    }
    fn context(self: *Renderer, scene: *ui.Scene, root_index: usize, depth: usize, order: []const usize, ctx: *anyopaque, draw: DrawFn, a: std.mem.Allocator) anyerror!rl.RenderTexture2D {
        const target_texture = try self.target(3 + depth);
        clear(target_texture, .blank);
        const root_item = scene.items.items[root_index];
        try self.drawItem(scene, root_item, target_texture, ctx, draw, a);
        for (order) |i| {
            const item = scene.items.items[i];
            if (scene.contextOwner(item) != root_item.node.id) continue;
            if (scene.establishesContext(item)) {
                const child = try self.context(scene, i, depth + 1, order, ctx, draw, a);
                self.composite(child.texture, target_texture, try self.mask(scene, item), std.math.clamp(item.node.style.opacity, 0, 1));
            } else try self.drawItem(scene, item, target_texture, ctx, draw, a);
        }
        return target_texture;
    }
    pub fn render(self: *Renderer, scene: *ui.Scene, ctx: *anyopaque, draw: DrawFn, a: std.mem.Allocator) !void {
        const width = rl.getScreenWidth();
        const height = rl.getScreenHeight();
        if (width != self.width or height != self.height) {
            for (self.targets.items) |t| rl.unloadRenderTexture(t);
            self.targets.clearRetainingCapacity();
            if (self.content_target) |t| rl.unloadRenderTexture(t);
            self.content_target = null;
            self.width = width;
            self.height = height;
        }
        const order = try scene.getPaintOrder(a);
        if (order.len == 0) return;
        const result = try self.context(scene, order[0], 0, order, ctx, draw, a);
        rl.beginBlendMode(.alpha_premultiply);
        // The screen is the only target with a background already present.
        rl.drawTexturePro(result.texture, .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = -@as(f32, @floatFromInt(height)) }, .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) }, .{ .x = 0, .y = 0 }, 0, .{ .r = @intFromFloat(std.math.clamp(scene.items.items[order[0]].node.style.opacity, 0, 1) * 255), .g = @intFromFloat(std.math.clamp(scene.items.items[order[0]].node.style.opacity, 0, 1) * 255), .b = @intFromFloat(std.math.clamp(scene.items.items[order[0]].node.style.opacity, 0, 1) * 255), .a = @intFromFloat(std.math.clamp(scene.items.items[order[0]].node.style.opacity, 0, 1) * 255) });
        rl.endBlendMode();
        var ids: std.ArrayList(u32) = .empty;
        defer ids.deinit(a);
        var it = self.cache.keyIterator();
        while (it.next()) |id| if (scene.find(id.*) == null) try ids.append(a, id.*);
        for (ids.items) |id| if (self.cache.fetchRemove(id)) |entry| {
            var c = entry.value;
            self.freeCached(&c);
        };
    }
};
