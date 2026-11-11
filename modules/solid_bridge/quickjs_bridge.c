#include "quickjs.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
static JSRuntime *runtime;
static JSContext *context;
static JSValue host_now(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val; (void)argc; (void)argv;
    struct timespec value;
    timespec_get(&value, TIME_UTC);
    return JS_NewFloat64(ctx, (double)value.tv_sec * 1000 + value.tv_nsec / 1000000.0);
}
static void report(void) {
    JSValue e = JS_GetException(context);
    const char *s = JS_ToCString(context, e);
    fprintf(stderr, "QuickJS: %s\n", s ? s : "unknown error");
    if (s) JS_FreeCString(context, s);
    JSValue stack = JS_GetPropertyStr(context, e, "stack");
    const char *trace = JS_ToCString(context, stack);
    if (trace) { fprintf(stderr, "%s\n", trace); JS_FreeCString(context, trace); }
    JS_FreeValue(context, stack);
    JS_FreeValue(context, e);
}
static int jobs(void) {
    JSContext *job_context;
    int result;
    while ((result = JS_ExecutePendingJob(runtime, &job_context)) > 0) {}
    if (result < 0) { report(); return 0; }
    return 1;
}
int ui_init(const char *source, size_t len) {
    runtime = JS_NewRuntime();
    if (!runtime) return 0;
    JS_SetMaxStackSize(runtime, 8 * 1024 * 1024);
    context = JS_NewContext(runtime);
    if (!context) return 0;
    JSValue global = JS_GetGlobalObject(context);
    JS_SetPropertyStr(context, global, "__nativeNow", JS_NewCFunction(context, host_now, "__nativeNow", 0));
    JS_FreeValue(context, global);
    const char *prelude =
        "globalThis.queueMicrotask = fn => Promise.resolve().then(fn);"
        "globalThis.console ||= {log(){},warn(){},error(){},info(){}};"
        "globalThis.__timers = new Map(); let __timerId = 0;"
        "globalThis.setTimeout = (fn,ms=0,...args) => { const id=++__timerId; __timers.set(id,{fn:()=>fn(...args),at:__nativeNow()+Math.max(0,Number(ms)||0)}); return id; };"
        "globalThis.clearTimeout = id => __timers.delete(id);"
        "globalThis.setInterval = (fn,ms=0,...args) => { const id=++__timerId; const delay=Math.max(1,Number(ms)||0); __timers.set(id,{fn:()=>fn(...args),at:__nativeNow()+delay,repeat:delay}); return id; };"
        "globalThis.clearInterval = clearTimeout;"
        "globalThis.__pumpTimers = () => { const now=__nativeNow(); let count=0; for(const [id,t] of __timers) { if(t.at>now)continue; if(++count>100)break; if(t.repeat)t.at=now+t.repeat;else __timers.delete(id); t.fn(); } };"
        "globalThis.__nextTimer = () => { let next=Infinity; for(const t of __timers.values())next=Math.min(next,t.at); return Number.isFinite(next)?Math.max(0,next-__nativeNow())/1000:-1; };";
    JSValue setup = JS_Eval(context, prelude, strlen(prelude), "native-runtime", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(setup)) { report(); JS_FreeValue(context, setup); return 0; }
    JS_FreeValue(context, setup);
    JSValue value = JS_Eval(context, source, len, "ui-bundle.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { report(); JS_FreeValue(context, value); return 0; }
    JS_FreeValue(context, value);
    return jobs();
}
int ui_eval(const char *code, char *out, size_t capacity) {
    JSValue value = JS_Eval(context, code, strlen(code), "host", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { report(); JS_FreeValue(context, value); return 0; }
    const char *text = JS_ToCString(context, value);
    if (!text) { JS_FreeValue(context, value); return 0; }
    snprintf(out, capacity, "%s", text);
    JS_FreeCString(context, text);
    JS_FreeValue(context, value);
    return jobs();
}
char *ui_eval_string(const char *code) {
    JSValue value = JS_Eval(context, code, strlen(code), "host", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { report(); JS_FreeValue(context, value); return NULL; }
    size_t len = 0;
    const char *text = JS_ToCStringLen(context, &len, value);
    if (!text) { JS_FreeValue(context, value); return NULL; }
    char *copy = malloc(len + 1);
    if (copy) { memcpy(copy, text, len); copy[len] = 0; }
    JS_FreeCString(context, text);
    JS_FreeValue(context, value);
    if (!jobs()) { free(copy); return NULL; }
    return copy;
}
void ui_free_string(char *value) { free(value); }
int ui_input(uint32_t id, const char *text) {
    JSValue global = JS_GetGlobalObject(context);
    JSValue handler = JS_GetPropertyStr(context, global, "uiDispatchInput");
    JSValue args[] = {JS_NewUint32(context, id), JS_NewString(context, text)};
    JSValue result = JS_Call(context, handler, global, 2, args);
    int ok = !JS_IsException(result);
    if (!ok) report();
    JS_FreeValue(context, result); JS_FreeValue(context, args[0]); JS_FreeValue(context, args[1]);
    JS_FreeValue(context, handler); JS_FreeValue(context, global);
    return ok && jobs();
}
int ui_tick(void) {
    char ignored[32];
    return ui_eval("__pumpTimers()", ignored, sizeof(ignored));
}
double ui_next_timeout(void) {
    JSValue value = JS_Eval(context, "__nextTimer()", 13, "scheduler", JS_EVAL_TYPE_GLOBAL);
    double delay = -1;
    if (JS_IsException(value)) report(); else JS_ToFloat64(context, &delay, value);
    JS_FreeValue(context, value);
    return delay;
}
void ui_destroy(void) {
    if (context) JS_FreeContext(context);
    if (runtime) JS_FreeRuntime(runtime);
    context = NULL; runtime = NULL;
}

int ui_reload(void) {
    FILE *file = fopen("src/ui-hmr.js", "rb");
    if (!file) return 0;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return 0; }
    long size = ftell(file);
    if (size <= 0 || size > 1024 * 1024 || fseek(file, 0, SEEK_SET) != 0) { fclose(file); return 0; }
    char *source = malloc((size_t)size + 1);
    if (!source) { fclose(file); return 0; }
    size_t read = fread(source, 1, (size_t)size, file);
    fclose(file);
    if (read != (size_t)size) { free(source); return 0; }
    source[size] = '\0';
    JSValue result = JS_Eval(context, source, (size_t)size, "vite-hmr", JS_EVAL_TYPE_GLOBAL);
    free(source);
    if (JS_IsException(result)) { report(); JS_FreeValue(context, result); return 0; }
    JS_FreeValue(context, result);
    return jobs();
}
