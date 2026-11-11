// Wake Raylib's event-waiting loop for QuickJS timer deadlines. QuickJS stays
// on the UI thread; the worker only posts a GLFW event.
#ifdef _WIN32
#include <windows.h>
#include <math.h>
extern void glfwPostEmptyEvent(void);
static HANDLE timer_handle, stop_event, worker;
static DWORD WINAPI timer_worker(LPVOID unused) {
    (void)unused;
    HANDLE handles[] = { stop_event, timer_handle };
    for (;;) {
        DWORD event = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
        if (event != WAIT_OBJECT_0 + 1) break;
        glfwPostEmptyEvent();
    }
    return 0;
}
int ui_wake_start(void) {
    timer_handle = CreateWaitableTimerW(NULL, FALSE, NULL);
    stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (timer_handle && stop_event) worker = CreateThread(NULL, 0, timer_worker, NULL, 0, NULL);
    if (worker) return 1;
    if (timer_handle) CloseHandle(timer_handle);
    if (stop_event) CloseHandle(stop_event);
    timer_handle = stop_event = NULL;
    return 0;
}
void ui_wake_schedule(double seconds) {
    if (!worker) return;
    if (!isfinite(seconds) || seconds < 0) { CancelWaitableTimer(timer_handle); return; }
    // Clamp to one day; an earlier OS event will recompute the deadline.
    if (seconds > 86400) seconds = 86400;
    LARGE_INTEGER due;
    due.QuadPart = -(LONGLONG)fmax(1, ceil(seconds * 10000000.0));
    SetWaitableTimer(timer_handle, &due, 0, NULL, NULL, FALSE);
}
void ui_wake_stop(void) {
    if (!worker) return;
    SetEvent(stop_event);
    WaitForSingleObject(worker, INFINITE);
    CloseHandle(worker); CloseHandle(timer_handle); CloseHandle(stop_event);
    worker = timer_handle = stop_event = NULL;
}
#else
int ui_wake_start(void) { return 0; }
void ui_wake_schedule(double seconds) { (void)seconds; }
void ui_wake_stop(void) {}
#endif
