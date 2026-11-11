#include <stdlib.h>
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
            if ((entry->Action == FILE_ACTION_RENAMED_NEW_NAME || entry->Action == FILE_ACTION_ADDED || entry->Action == FILE_ACTION_MODIFIED) &&
                entry->FileNameLength == sizeof(name) - sizeof(wchar_t) &&
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


