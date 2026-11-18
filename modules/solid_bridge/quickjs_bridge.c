#include "quickjs.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <stddef.h>
#include "runtime_probes.h"
#ifdef _WIN32
#include <windows.h>
#endif
static JSRuntime *runtime;
static JSContext *context;
extern double host_app_now(void);
extern int host_controlled(void);
extern uint64_t host_timer_add(double ms, int kind);
extern void host_timer_cancel(uint64_t id);
uint64_t ui_real_ns(void) {
#ifdef _WIN32
    LARGE_INTEGER c, f; QueryPerformanceCounter(&c); QueryPerformanceFrequency(&f);
    return (uint64_t)(c.QuadPart / f.QuadPart) * 1000000000ULL + (uint64_t)(c.QuadPart % f.QuadPart) * 1000000000ULL / f.QuadPart;
#else
    struct timespec v; clock_gettime(CLOCK_MONOTONIC, &v); return (uint64_t)v.tv_sec * 1000000000ULL + v.tv_nsec;
#endif
}
uint64_t ui_cpu_ns(void) {
#ifdef _WIN32
    FILETIME a,b,k,u;GetProcessTimes(GetCurrentProcess(),&a,&b,&k,&u);
    ULARGE_INTEGER kernel,user;kernel.LowPart=k.dwLowDateTime;kernel.HighPart=k.dwHighDateTime;user.LowPart=u.dwLowDateTime;user.HighPart=u.dwHighDateTime;
    return (kernel.QuadPart+user.QuadPart)*100;
#else
    return (uint64_t)clock()*1000000000ULL/CLOCKS_PER_SEC;
#endif
}
static uint64_t watchdog;
void ui_watchdog_start(void) { watchdog = ui_real_ns() + 5000000000ULL; }
void ui_watchdog_stop(void) { watchdog = 0; }
static int interrupt(JSRuntime *rt, void *opaque) { (void)rt; (void)opaque; return watchdog && ui_real_ns() >= watchdog; }
#define TIMER_CAPACITY 4096
typedef struct { uint64_t id; JSValue callback, args; } Callback;
static Callback callbacks[TIMER_CAPACITY];
void ui_timer_release(uint64_t id) {
    Callback *slot = &callbacks[id % TIMER_CAPACITY];
    if (!id || slot->id != id) return;
    JS_FreeValue(context, slot->callback); JS_FreeValue(context, slot->args); slot->id = 0;
#if UI_PROBES
    memory.roots--;
#endif
}
static JSValue host_schedule(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv, int kind) {
    (void)self;
    if (argc < 1 || !JS_IsFunction(ctx, argv[0])) return JS_ThrowTypeError(ctx, "timer callback must be callable");
    if(argc>66)return JS_ThrowRangeError(ctx,"timers support up to 64 arguments");
    double delay = 0;
    if (kind != 2 && argc > 1 && JS_ToFloat64(ctx, &delay, argv[1]) < 0) return JS_EXCEPTION;
    // Callable-only compatibility: NaN/negative => 0, +Infinity/oversize =>
    // 2^31-1 ms; intervals have a 1-ms minimum. No signed wraparound.
    if (isnan(delay) || delay < 0) delay = 0;
    if (delay > 2147483647.0) delay = 2147483647.0;
    if (kind == 1 && delay < 1) delay = 1;
    JSValue args = JS_NewArray(ctx);
    if (JS_IsException(args)) return args;
    for (int i = 2; i < argc && kind != 2; i++) {
        if (JS_SetPropertyUint32(ctx, args, i - 2, JS_DupValue(ctx, argv[i])) < 0) { JS_FreeValue(ctx, args); return JS_EXCEPTION; }
    }
    uint64_t id = host_timer_add(delay, kind);
    if (!id) { JS_FreeValue(ctx, args); return JS_ThrowRangeError(ctx, "timer capacity, deadline or ID limit"); }
    Callback *slot = &callbacks[id % TIMER_CAPACITY];
    slot->id = id; slot->callback = JS_DupValue(ctx, argv[0]); slot->args = args;
#if UI_PROBES
    memory.roots++;
#endif
    return JS_NewFloat64(ctx, (double)id);
}
static JSValue host_cancel(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; double id = 0;
    if (argc && JS_ToFloat64(ctx, &id, argv[0]) < 0) return JS_EXCEPTION;
    if (isfinite(id) && id > 0 && id <= 9007199254740991.0 && floor(id) == id) host_timer_cancel((uint64_t)id);
    return JS_UNDEFINED;
}
int ui_jobs(void);
static void report(void);
int ui_timer_call(uint64_t id, double timestamp, int once, int raf) {
    Callback *slot = &callbacks[id % TIMER_CAPACITY];
    if (slot->id != id) return 1;
    JSValue fn = JS_DupValue(context, slot->callback), args = JS_DupValue(context, slot->args);
    if (once) ui_timer_release(id);
    JSValue result;
    if (raf) { JSValue at = JS_NewFloat64(context, timestamp); result = JS_Call(context, fn, JS_UNDEFINED, 1, &at); JS_FreeValue(context, at); }
    else {
        JSValue length=JS_GetPropertyStr(context,args,"length");uint32_t count=0;JS_ToUint32(context,&count,length);JS_FreeValue(context,length);
        JSValue av[64];for(uint32_t i=0;i<count;i++)av[i]=JS_GetPropertyUint32(context,args,i);
        result=JS_Call(context,fn,JS_UNDEFINED,count,av);
        for(uint32_t i=0;i<count;i++)JS_FreeValue(context,av[i]);
    }
    int ok = !JS_IsException(result); if (!ok) report();
    JS_FreeValue(context, result); JS_FreeValue(context, fn); JS_FreeValue(context, args);
    return ok && ui_jobs();
}
static JSValue host_now(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val; (void)argc; (void)argv;
    return JS_NewFloat64(ctx, host_app_now());
}
static JSValue host_log(JSContext *ctx, JSValueConst this_val, int argc, JSValueConst *argv) {
    (void)this_val;
    for (int i = 0; i < argc; i++) {
        const char *value = JS_ToCString(ctx, argv[i]);
        if (!value) return JS_EXCEPTION;
        fprintf(stderr, "%s%s", i ? " " : "", value);
        record_log(value);
        JS_FreeCString(ctx, value);
    }
    fputc('\n', stderr);
    return JS_UNDEFINED;
}
static void report(void) {
    JSValue e = JS_GetException(context);
    const char *s = JS_ToCString(context, e);
    fprintf(stderr, "QuickJS: %s\n", s ? s : "unknown error");
    record_log(s?s:"unknown error");
    if (s) JS_FreeCString(context, s);
    JSValue stack = JS_GetPropertyStr(context, e, "stack");
    const char *trace = JS_ToCString(context, stack);
    if (trace) { fprintf(stderr, "%s\n", trace); JS_FreeCString(context, trace); }
    JS_FreeValue(context, stack);
    JS_FreeValue(context, e);
}
int ui_jobs(void) {
    JSContext *job_context;
    int result;
    unsigned int count = 0;
    while ((result = JS_ExecutePendingJob(runtime, &job_context)) > 0 && ++count < 1024) {}
    if (result < 0) { report(); return 0; }
    if (JS_IsJobPending(runtime)) { fprintf(stderr, "QuickJS: job budget exhausted\n"); return 0; }
    return 1;
}
#define jobs ui_jobs
static int init_source(const char *source, size_t len) {
    if (runtime) return -1;
    memset(&memory,0,sizeof(memory));log_count=log_dropped=0;
    ui_watchdog_start();
#if UI_PROBES
    runtime = JS_NewRuntime2(&tracked_functions,NULL);
#else
    runtime = JS_NewRuntime();
#endif
    if (!runtime) return 0;
    JS_SetMaxStackSize(runtime, 8 * 1024 * 1024);
    JS_SetInterruptHandler(runtime, interrupt, NULL);
    context = JS_NewContext(runtime);
    if (!context) return 0;
    JSValue global = JS_GetGlobalObject(context);
    JS_SetPropertyStr(context, global, "__nativeNow", JS_NewCFunction(context, host_now, "__nativeNow", 0));
    JS_SetPropertyStr(context, global, "__nativeLog", JS_NewCFunction(context, host_log, "__nativeLog", 1));
    JS_SetPropertyStr(context, global, "setTimeout", JS_NewCFunctionMagic(context, host_schedule, "setTimeout", 1, JS_CFUNC_generic_magic, 0));
    JS_SetPropertyStr(context, global, "setInterval", JS_NewCFunctionMagic(context, host_schedule, "setInterval", 1, JS_CFUNC_generic_magic, 1));
    JS_SetPropertyStr(context, global, "requestAnimationFrame", JS_NewCFunctionMagic(context, host_schedule, "requestAnimationFrame", 1, JS_CFUNC_generic_magic, 2));
    JS_SetPropertyStr(context, global, "clearTimeout", JS_NewCFunction(context, host_cancel, "clearTimeout", 1));
    JS_SetPropertyStr(context, global, "clearInterval", JS_NewCFunction(context, host_cancel, "clearInterval", 1));
    JS_SetPropertyStr(context, global, "cancelAnimationFrame", JS_NewCFunction(context, host_cancel, "cancelAnimationFrame", 1));
    JS_FreeValue(context, global);
    const char *prelude =
        "globalThis.queueMicrotask = fn => Promise.resolve().then(fn);"
        "globalThis.console ||= {log:__nativeLog,warn:__nativeLog,error:__nativeLog,info:__nativeLog,debug:__nativeLog};"
        "globalThis.performance = {now:__nativeNow};";
    JSValue setup = JS_Eval(context, prelude, strlen(prelude), "native-runtime", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(setup)) { report(); JS_FreeValue(context, setup); return 0; }
    JS_FreeValue(context, setup);
    if (host_controlled()) {
        const char *date = "{const D=Date; const C=new Proxy(D,{apply(){return new D(1700000000000+__nativeNow()).toString()},construct(t,a,n){return Reflect.construct(t,a.length?a:[1700000000000+__nativeNow()],n)}});Object.defineProperty(C,'now',{value:()=>1700000000000+__nativeNow(),writable:true,configurable:true});Object.defineProperty(D.prototype,'constructor',{value:C,writable:true,configurable:true});globalThis.Date=C;}";
        setup = JS_Eval(context, date, strlen(date), "controlled-date", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(setup)) { report(); JS_FreeValue(context, setup); return 0; } JS_FreeValue(context, setup);
    }
    JSValue value = JS_Eval(context, source, len, "ui-bundle.js", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { report(); JS_FreeValue(context, value); return 0; }
    JS_FreeValue(context, value);
    int ok=jobs();ui_watchdog_stop();return ok;
}
int ui_init(const char *source, size_t len) { return init_source(source,len); }
int ui_init_driver(const char *source, size_t len) {
#if UI_PROBES
    // A driver build may select its app at startup, like the existing dev HMR
    // loader. No protocol command evaluates source; ordinary builds omit this.
    const char *path=getenv("SOLID_NATIVE_DRIVER_SOURCE");
    if(path){
        FILE *file=fopen(path,"rb");if(!file)return 0;
        if(fseek(file,0,SEEK_END)!=0){fclose(file);return 0;}
        long bytes=ftell(file);
        if(bytes<=0 || bytes>32*1024*1024 || fseek(file,0,SEEK_SET)!=0){fclose(file);return 0;}
        char *owned=malloc((size_t)bytes);if(!owned){fclose(file);return 0;}
        size_t read=fread(owned,1,(size_t)bytes,file);fclose(file);
        if(read!=(size_t)bytes){free(owned);return 0;}
        int result=init_source(owned,read);free(owned);return result;
    }
#endif
    return init_source(source,len);
}
int ui_eval(const char *code, char *out, size_t capacity) {
    ui_watchdog_start();
    JSValue value = JS_Eval(context, code, strlen(code), "host", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(value)) { report(); JS_FreeValue(context, value); return 0; }
    const char *text = JS_ToCString(context, value);
    if (!text) { JS_FreeValue(context, value); return 0; }
    snprintf(out, capacity, "%s", text);
    JS_FreeCString(context, text);
    JS_FreeValue(context, value);
    int ok=jobs();ui_watchdog_stop();return ok;
}
char *ui_eval_string(const char *code) {
    ui_watchdog_start();
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
    ui_watchdog_stop();return copy;
}
void ui_free_string(char *value) { free(value); }
int ui_input(uint32_t id, const char *text) {
    ui_watchdog_start();
    JSValue global = JS_GetGlobalObject(context);
    JSValue handler = JS_GetPropertyStr(context, global, "uiDispatchInput");
    JSValue args[] = {JS_NewUint32(context, id), JS_NewString(context, text)};
    JSValue result = JS_Call(context, handler, global, 2, args);
    int ok = !JS_IsException(result);
    if (!ok) report();
    JS_FreeValue(context, result); JS_FreeValue(context, args[0]); JS_FreeValue(context, args[1]);
    JS_FreeValue(context, handler); JS_FreeValue(context, global);
    ok=ok && jobs();ui_watchdog_stop();return ok;
}
int ui_tick(void) {
    return jobs();
}
double ui_next_timeout(void) {
    return JS_IsJobPending(runtime) ? 0 : -1;
}
void ui_destroy(void) {
    ui_watchdog_start();
    if (context) {
        const char *cleanup = "if(typeof uiDispose==='function')uiDispose()";
        JSValue result = JS_Eval(context, cleanup, strlen(cleanup), "shutdown", JS_EVAL_TYPE_GLOBAL);
        if (JS_IsException(result)) report();
        JS_FreeValue(context, result);
        jobs();
    }
    if (context) for (size_t i=0; i<TIMER_CAPACITY; ++i) ui_timer_release(callbacks[i].id);
    if (context) JS_FreeContext(context);
    if (runtime) JS_FreeRuntime(runtime);
    context = NULL; runtime = NULL;
    ui_watchdog_stop();
}

int ui_reload(void) {
    ui_watchdog_start();
    FILE *file = fopen("src/ui-hmr.js", "rb");
    if (!file) return 0;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return 0; }
    long size = ftell(file);
    if (size <= 0 || size > 32 * 1024 * 1024 || fseek(file, 0, SEEK_SET) != 0) {
        fprintf(stderr, "QuickJS: invalid development graph size (limit 32 MiB)\n");
        fclose(file); return 0;
    }
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
