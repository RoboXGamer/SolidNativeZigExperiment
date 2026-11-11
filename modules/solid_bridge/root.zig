//! QuickJS host interface. This module owns no UI layout or drawing.
const std = @import("std");
extern fn ui_init(source: [*]const u8, len: usize) c_int;
extern fn ui_eval(code: [*:0]const u8, out: [*]u8, capacity: usize) c_int;
extern fn ui_eval_string(code: [*:0]const u8) ?[*:0]u8;
extern fn ui_free_string(value: [*:0]u8) void;
extern fn ui_destroy() void;
extern fn ui_reload() c_int;
extern fn ui_tick() c_int;
extern fn ui_next_timeout() f64;
extern fn ui_input(id: u32, text: [*:0]const u8) c_int;

pub const Runtime = struct {
    pub fn input(_: *Runtime, id: u32, text: [:0]const u8) !void {
        if (ui_input(id, text.ptr) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn acknowledge(_: *Runtime) !void {
        var ignored: [32]u8 = undefined;
        if (ui_eval("uiCommit()", &ignored, ignored.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn tick(_: *Runtime) !void {
        if (ui_tick() == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn nextTimeout(_: *Runtime) f64 {
        return ui_next_timeout();
    }
    pub fn init(source: []const u8) !Runtime {
        const result = ui_init(source.ptr, source.len);
        if (result < 0) return error.RuntimeAlreadyInitialized;
        if (result == 0) {
            ui_destroy();
            return error.JavaScriptInitializationFailed;
        }
        return .{};
    }
    pub fn deinit(_: *Runtime) void {
        ui_destroy();
    }
    pub fn changes(_: *Runtime) ![:0]u8 {
        const result = ui_eval_string("uiChanges()") orelse return error.JavaScriptEvaluationFailed;
        return std.mem.span(result);
    }
    pub fn freeChanges(_: *Runtime, value: [:0]u8) void {
        ui_free_string(value.ptr);
    }
    pub fn click(_: *Runtime, id: u32) !void {
        var command: [64]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "uiDispatchClick({d})", .{id});
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn key(_: *Runtime, id: u32, key_name: []const u8) !void {
        var command: [128]u8 = undefined;
        const expression = try std.fmt.bufPrint(command[0 .. command.len - 1], "uiDispatchKey({d},\"{s}\")", .{ id, key_name });
        command[expression.len] = 0;
        var result: [32]u8 = undefined;
        if (ui_eval(@ptrCast(expression.ptr), &result, result.len) == 0) return error.JavaScriptEvaluationFailed;
    }
    pub fn reload(_: *Runtime) bool {
        return ui_reload() != 0;
    }
};
