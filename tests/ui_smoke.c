#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int ui_init(const char *source, size_t len);
extern int ui_eval(const char *code, char *out, size_t capacity);
extern void ui_destroy(void);
extern int ui_tick(void);
#ifdef _WIN32
#include <windows.h>
#endif
#ifdef _WIN32
void glfwPostEmptyEvent(void) {}
#endif

static int expect(const char *expression, const char *expected) {
    char out[256] = {0};
    if (!ui_eval(expression, out, sizeof(out)) || strcmp(out, expected) != 0) {
        fprintf(stderr, "Expected %s => %s; got %s\n", expression, expected, out);
        return 0;
    }
    return 1;
}

int main(void) {
    FILE *file = fopen("src/ui-bundle.js", "rb");
    if (!file) return 1;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return 1; }
    long length = ftell(file);
    if (length <= 0 || fseek(file, 0, SEEK_SET) != 0) { fclose(file); return 1; }
    char *source = malloc((size_t)length);
    if (!source) { fclose(file); return 1; }
    size_t read = fread(source, 1, (size_t)length, file);
    fclose(file);
    int ok = read == (size_t)length && ui_init(source, read);
    free(source);
    char label[256], expected[256];
    int initial = 0;
    if (ok) ok = ui_eval("uiLabel()", label, sizeof(label)) && sscanf(label, "Count: %d", &initial) == 1 &&
                 expect("uiButton()", "Increment") && ui_eval("uiClick()", (char[256]){0}, 256);
    int after_first = initial;
    if (ok) ok = ui_eval("uiLabel()", label, sizeof(label)) && sscanf(label, "Count: %d", &after_first) == 1;
    int delta = after_first - initial;
    snprintf(expected, sizeof(expected), "Count: %d", after_first);
    if (ok) ok = expect("uiLabel()", expected) && ui_eval("uiClick()", (char[256]){0}, 256);
    snprintf(expected, sizeof(expected), "Count: %d", initial + delta * 2);
    if (ok) ok = expect("uiLabel()", expected);
    if (ok) ok = expect("(() => { const tree = JSON.parse(uiSnapshot()); const column = tree.children[0]; return column.type === 'column' && column.children.some(n => n.type === 'button' && n.clickable && n.id > 0); })()", "true");
    if (ok) ok = ui_eval("uiDispatchClick(JSON.parse(uiSnapshot()).children[0].children.find(n => n.type === 'button').id)", (char[256]){0}, 256);
    snprintf(expected, sizeof(expected), "Count: %d", initial + delta * 3);
    if (ok) ok = expect("uiLabel()", expected);
    if (ok) {
        FILE *features = fopen("tests/features.js", "rb");
        if (!features) ok = 0;
        else {
            char script[16384];
            size_t length = fread(script, 1, sizeof(script) - 1, features);
            fclose(features); script[length] = 0;
            ok = ui_eval(script, label, sizeof(label));
            for (int i = 0; ok && i < 100; i++) {
                ok = ui_tick() && ui_eval("__featureResult", label, sizeof(label));
                if (!ok || strcmp(label, "passed") == 0) break;
#ifdef _WIN32
                Sleep(1);
#endif
            }
            if (ok) ok = strcmp(label, "passed") == 0;
        }
    }
    ui_destroy();
    if (!ok) return 1;
    puts("QuickJS Solid counter smoke test passed");
    return 0;
}
