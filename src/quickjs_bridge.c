#include "quickjs.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static JSRuntime *runtime;
static JSContext *context;
static void report(void) {
    JSValue e = JS_GetException(context);
    const char *s = JS_ToCString(context, e);
    fprintf(stderr, "QuickJS: %s\n", s ? s : "unknown error");
    if (s) JS_FreeCString(context, s);
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
void ui_destroy(void) {
    if (context) JS_FreeContext(context);
    if (runtime) JS_FreeRuntime(runtime);
    context = NULL; runtime = NULL;
}

#ifdef _WIN32
#include <windows.h>
extern void glfwPostEmptyEvent(void);
static HANDLE watch_dir = INVALID_HANDLE_VALUE, watch_thread, watch_stop_event;
static volatile LONG watch_changed, watch_stopping;
static DWORD WINAPI watch_main(LPVOID unused) {
    (void)unused;
    char buffer[4096]; DWORD bytes;
    OVERLAPPED op = {0};
    op.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!op.hEvent) return 0;
    while (!InterlockedCompareExchange(&watch_stopping, 0, 0)) {
        ResetEvent(op.hEvent);
        if (!ReadDirectoryChangesW(watch_dir, buffer, sizeof(buffer), FALSE,
                FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_SIZE,
                NULL, &op, NULL)) break;
        HANDLE events[] = {watch_stop_event, op.hEvent};
        if (WaitForMultipleObjects(2, events, FALSE, INFINITE) != WAIT_OBJECT_0 + 1) {
            CancelIoEx(watch_dir, &op);
            GetOverlappedResult(watch_dir, &op, &bytes, TRUE);
            break;
        }
        if (!GetOverlappedResult(watch_dir, &op, &bytes, FALSE)) break;
        for (DWORD offset = 0; offset < bytes;) {
            FILE_NOTIFY_INFORMATION *entry = (FILE_NOTIFY_INFORMATION *)(buffer + offset);
            const wchar_t name[] = L"ui-hmr.js";
            if (entry->FileNameLength == sizeof(name) - sizeof(wchar_t) &&
                _wcsnicmp(entry->FileName, name, entry->FileNameLength / sizeof(wchar_t)) == 0) {
                InterlockedExchange(&watch_changed, 1);
                glfwPostEmptyEvent();
            }
            if (!entry->NextEntryOffset) break;
            offset += entry->NextEntryOffset;
        }
    }
    CloseHandle(op.hEvent);
    return 0;
}
int ui_watch_start(void) {
    if (!getenv("DRAFT1_HMR")) return 0;
    watch_dir = CreateFileW(L"src", FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
    if (watch_dir == INVALID_HANDLE_VALUE) return 0;
    watch_stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!watch_stop_event) { CloseHandle(watch_dir); watch_dir = INVALID_HANDLE_VALUE; return 0; }
    InterlockedExchange(&watch_stopping, 0);
    watch_thread = CreateThread(NULL, 0, watch_main, NULL, 0, NULL);
    if (!watch_thread) { CloseHandle(watch_stop_event); CloseHandle(watch_dir); watch_dir = INVALID_HANDLE_VALUE; return 0; }
    return 1;
}
int ui_watch_changed(void) { return (int)InterlockedExchange(&watch_changed, 0); }
void ui_watch_stop(void) {
    if (!watch_thread) return;
    InterlockedExchange(&watch_stopping, 1);
    SetEvent(watch_stop_event);
    WaitForSingleObject(watch_thread, INFINITE);
    CloseHandle(watch_thread); watch_thread = NULL;
    CloseHandle(watch_stop_event); watch_stop_event = NULL;
    CloseHandle(watch_dir); watch_dir = INVALID_HANDLE_VALUE;
}
#else
int ui_watch_start(void) { return 0; }
int ui_watch_changed(void) { return 0; }
void ui_watch_stop(void) {}
#endif


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
