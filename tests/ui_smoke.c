#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int ui_init(const char *source, size_t len);
extern int ui_eval(const char *code, char *out, size_t capacity);
extern void ui_destroy(void);
#ifdef _WIN32
void glfwPostEmptyEvent(void) {}
#endif

static int expect(const char *expression, const char *expected) {
    char out[256];
    if (!ui_eval(expression, out, sizeof(out)) || strcmp(out, expected) != 0) {
        fprintf(stderr, "Expected %s => %s\n", expression, expected);
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
    snprintf(expected, sizeof(expected), "Count: %d", initial + 1);
    if (ok) ok = expect("uiLabel()", expected) && ui_eval("uiClick()", (char[256]){0}, 256);
    snprintf(expected, sizeof(expected), "Count: %d", initial + 2);
    if (ok) ok = expect("uiLabel()", expected);
    ui_destroy();
    if (!ok) return 1;
    puts("QuickJS Solid counter smoke test passed");
    return 0;
}
