// Wake Raylib's event-waiting loop for QuickJS timer deadlines. QuickJS stays
// on the UI thread; the worker only posts a GLFW event.
#ifdef _WIN32
#include <windows.h>
#include <math.h>
extern void glfwPostEmptyEvent(void);
typedef struct GLFWwindow GLFWwindow;
typedef void (*RefreshCallback)(GLFWwindow*);
extern GLFWwindow *glfwGetCurrentContext(void);
extern RefreshCallback glfwSetWindowRefreshCallback(GLFWwindow*, RefreshCallback);
static GLFWwindow *refresh_window;
static RefreshCallback previous_refresh;
static int refresh_pending;
static void refresh_callback(GLFWwindow *window) {
    refresh_pending = 1;
    if (previous_refresh) previous_refresh(window);
}
void ui_refresh_start(void) {
    refresh_window = glfwGetCurrentContext();
    if (refresh_window) previous_refresh = glfwSetWindowRefreshCallback(refresh_window, refresh_callback);
}
int ui_refresh_changed(void) { int changed = refresh_pending; refresh_pending = 0; return changed; }
void ui_refresh_stop(void) {
    if (refresh_window) glfwSetWindowRefreshCallback(refresh_window, previous_refresh);
    refresh_window = NULL; previous_refresh = NULL; refresh_pending = 0;
}
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
void ui_refresh_start(void) {}
int ui_refresh_changed(void) { return 0; }
void ui_refresh_stop(void) {}
int ui_wake_start(void) { return 0; }
void ui_wake_schedule(double seconds) { (void)seconds; }
void ui_wake_stop(void) {}
#endif
