// Standalone real-C-bridge regression; timers are outside this fixture's scope.
#include <stdio.h>
#include <string.h>
#include <stdint.h>
extern int ui_init(const char *, size_t);
extern int ui_tick(void);
extern void ui_destroy(void);
extern int ui_eval(const char *, char *, size_t);
extern int ui_unhandled_count(void);
double host_app_now(void) { return 0; }
int host_controlled(void) { return 0; }
uint64_t host_timer_add(double ms, int kind) { (void)ms; (void)kind; return 0; }
void host_timer_cancel(uint64_t id) { (void)id; }
int main(void) {
    const char *source = "globalThis.uiDispose=()=>{};globalThis.p=null;";
    int boot = ui_init(source, strlen(source));
    char result[32];
    int rejected=ui_eval("p=Promise.reject(Error('AUDIT_UNHANDLED_REJECTION'));",result,sizeof(result));
    int tracked=ui_unhandled_count();
    int handled=ui_eval("p.catch(()=>{});'handled'",result,sizeof(result));
    int released=ui_unhandled_count()==0;
    printf("HMR_VM_REJECTION boot=%d rejected=%d tracked=%d handled=%d released=%d\n",boot,rejected,tracked,handled,released);
    ui_destroy();
    return !(boot && !rejected && tracked==1 && handled && released);
}
