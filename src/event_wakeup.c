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
static SRWLOCK timer_lock = SRWLOCK_INIT;
static ULONGLONG deadline_ticks;
static volatile LONG64 wake_generation;
static ULONGLONG wake_now(void) { LARGE_INTEGER now; QueryPerformanceCounter(&now); return (ULONGLONG)now.QuadPart; }
static ULONGLONG wake_frequency(void) { LARGE_INTEGER frequency; QueryPerformanceFrequency(&frequency); return (ULONGLONG)frequency.QuadPart; }
static int deliver_wake(LONG64 observed) {
    int delivered=0;
    AcquireSRWLockExclusive(&timer_lock);
    if(deadline_ticks && observed==InterlockedCompareExchange64(&wake_generation,0,0)){
        ULONGLONG now=wake_now();
        if(now>=deadline_ticks){deadline_ticks=0;glfwPostEmptyEvent();delivered=1;}
        else { // A one-shot OS timer can signal early; never lose the wake.
            LARGE_INTEGER due; due.QuadPart=-(LONGLONG)fmax(1,ceil((double)(deadline_ticks-now)*10000000.0/(double)wake_frequency()));
            SetWaitableTimer(timer_handle,&due,0,NULL,NULL,FALSE);
        }
    }
    ReleaseSRWLockExclusive(&timer_lock);return delivered;
}
#ifdef UI_DRIVER
int ui_wake_test_stale(void){
    LONG64 stale=InterlockedCompareExchange64(&wake_generation,0,0);
    AcquireSRWLockExclusive(&timer_lock);InterlockedIncrement64(&wake_generation);deadline_ticks=wake_now();ReleaseSRWLockExclusive(&timer_lock);
    int rejected=!deliver_wake(stale);
    AcquireSRWLockExclusive(&timer_lock);deadline_ticks=0;ReleaseSRWLockExclusive(&timer_lock);
    return rejected;
}
#endif
static DWORD WINAPI timer_worker(LPVOID unused) {
    (void)unused;
    HANDLE handles[] = { stop_event, timer_handle };
    for (;;) {
        DWORD event = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
        if (event != WAIT_OBJECT_0 + 1) break;
        LONG64 observed = InterlockedCompareExchange64(&wake_generation,0,0);
        // A cancelled/older OS delivery cannot authorize application callbacks.
        // Also reject an already-signalled timer after a later re-arm.
        deliver_wake(observed);
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
    AcquireSRWLockExclusive(&timer_lock);
    InterlockedIncrement64(&wake_generation);
    if (!isfinite(seconds) || seconds < 0) { deadline_ticks=0; CancelWaitableTimer(timer_handle); ReleaseSRWLockExclusive(&timer_lock); return; }
    // Clamp to one day; an earlier OS event will recompute the deadline.
    if (seconds > 86400) seconds = 86400;
    LARGE_INTEGER due;
    due.QuadPart = -(LONGLONG)fmax(1, ceil(seconds * 10000000.0));
    deadline_ticks=wake_now()+(ULONGLONG)ceil(seconds*(double)wake_frequency());
    SetWaitableTimer(timer_handle, &due, 0, NULL, NULL, FALSE);
    ReleaseSRWLockExclusive(&timer_lock);
}
void ui_wake_stop(void) {
    if (!worker) return;
    AcquireSRWLockExclusive(&timer_lock);InterlockedIncrement64(&wake_generation);deadline_ticks=0;ReleaseSRWLockExclusive(&timer_lock);
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
