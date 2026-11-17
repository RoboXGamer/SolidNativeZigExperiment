// Diagnostic fixture for the current bridge; not a passing future regression.
#include <stdio.h>
#include <string.h>
extern int ui_init(const char *, size_t);
extern int ui_tick(void);
extern void ui_destroy(void);
int main(void) {
    const char *source = "globalThis.uiDispose=()=>{};Promise.reject(Error('AUDIT_UNHANDLED_REJECTION'));";
    int boot = ui_init(source, strlen(source));
    int tick = ui_tick();
    printf("AUDIT_VM_RESULT init=%d tick=%d\n", boot, tick);
    ui_destroy();
    return !(boot && tick);
}
