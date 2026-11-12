// Native cursors, owned resource handles and bounded lookup cache. Resource URLs
// resolve as local/file paths relative to the process working directory. Network,
// data URLs, CSS escapes and SVG decoding are outside this local renderer.
#include <stddef.h>
#ifdef _WIN32
#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>
#undef LoadImage
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

// Raylib's public C ABI; image data remains Raylib-owned until UnloadImage.
typedef struct { void *data; int width, height, mipmaps, format; } CursorImage;
extern CursorImage LoadImage(const char *fileName);
extern void ImageFormat(CursorImage *image, int newFormat);
extern void UnloadImage(CursorImage image);
typedef struct { char *key; HCURSOR handle; } CursorEntry;
static CursorEntry cursor_cache[32];
static unsigned cursor_next;

static char *copy_range(const char *start, size_t length) {
    char *result = (char *)malloc(length + 1);
    if (result) { memcpy(result, start, length); result[length] = 0; }
    return result;
}
static char *trim(char *text) {
    while (isspace((unsigned char)*text)) ++text;
    size_t length = strlen(text);
    while (length && isspace((unsigned char)text[length - 1])) text[--length] = 0;
    return text;
}
static wchar_t *wide_path(const char *path) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) return NULL;
    wchar_t *wide = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
    if (wide) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, count);
    return wide;
}
static HCURSOR image_cursor(const char *path, int hx, int hy) {
    CursorImage image = LoadImage(path);
    if (!image.data) return NULL;
    // Windows supports larger cursors, but bound allocations for CSS resources.
    if (image.width <= 0 || image.height <= 0 || image.width > 256 || image.height > 256) { UnloadImage(image); return NULL; }
    ImageFormat(&image, 7); // PIXELFORMAT_UNCOMPRESSED_R8G8B8A8
    if (!image.data || image.format != 7) { UnloadImage(image); return NULL; }
    BITMAPINFO info;
    memset(&info, 0, sizeof(info));
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = image.width;
    info.bmiHeader.biHeight = -image.height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    unsigned char *pixels = NULL;
    HBITMAP color = CreateDIBSection(NULL, &info, DIB_RGB_COLORS, (void **)&pixels, NULL, 0);
    size_t mask_size = (size_t)((image.width + 15) / 16 * 2) * (size_t)image.height;
    void *mask_bits = calloc(mask_size, 1);
    HBITMAP mask = mask_bits ? CreateBitmap(image.width, image.height, 1, 1, mask_bits) : NULL;
    free(mask_bits);
    HCURSOR cursor = NULL;
    if (color && mask && pixels) {
        unsigned char *rgba = (unsigned char *)image.data;
        for (size_t i = 0; i < (size_t)image.width * (size_t)image.height; ++i) {
            unsigned alpha = rgba[i * 4 + 3];
            pixels[i * 4] = (unsigned char)(rgba[i * 4 + 2] * alpha / 255);
            pixels[i * 4 + 1] = (unsigned char)(rgba[i * 4 + 1] * alpha / 255);
            pixels[i * 4 + 2] = (unsigned char)(rgba[i * 4] * alpha / 255);
            pixels[i * 4 + 3] = (unsigned char)alpha;
        }
        ICONINFO icon;
        memset(&icon, 0, sizeof(icon));
        icon.xHotspot = (DWORD)(hx < 0 ? 0 : hx >= image.width ? image.width - 1 : hx);
        icon.yHotspot = (DWORD)(hy < 0 ? 0 : hy >= image.height ? image.height - 1 : hy);
        icon.hbmColor = color; icon.hbmMask = mask;
        cursor = (HCURSOR)CreateIconIndirect(&icon);
    }
    if (color) DeleteObject(color);
    if (mask) DeleteObject(mask);
    UnloadImage(image);
    return cursor;
}
static HCURSOR resource_cursor(char *candidate) {
    for (unsigned i = 0; i < 32; ++i) if (cursor_cache[i].key && !strcmp(cursor_cache[i].key, candidate)) return cursor_cache[i].handle;
    char *key = copy_range(candidate, strlen(candidate));
    if (!key) return NULL;
    char *path = candidate + 4;
    while (isspace((unsigned char)*path)) ++path;
    char quote = (*path == '\'' || *path == '"') ? *path++ : 0;
    char *end = path;
    if (quote) { while (*end && *end != quote) ++end; } else { while (*end && *end != ')') ++end; }
    if (!*end) { free(key); return NULL; }
    char *close = quote ? strchr(end + 1, ')') : end;
    if (!close) { free(key); return NULL; }
    float x = 0, y = 0;
    char *tail = close + 1;
    while (isspace((unsigned char)*tail)) ++tail;
    int custom_hotspot = *tail != 0;
    if (custom_hotspot) {
        char *after_x, *after_y;
        x = strtof(tail, &after_x); y = strtof(after_x, &after_y);
        if (after_x == tail || after_y == after_x || *trim(after_y) || !isfinite(x) || !isfinite(y) || fabsf(x) > 65535 || fabsf(y) > 65535) { free(key); return NULL; }
    }
    *end = 0;
    path = trim(path);
    if (!_strnicmp(path, "file:///", 8)) path += 8;
    // HTTP/data resources intentionally fall through to the CSS keyword.
    if (strstr(path, "://") || !_strnicmp(path, "data:", 5)) { free(key); return NULL; }
    wchar_t *wide = wide_path(path);
    HCURSOR cursor = wide ? (HCURSOR)LoadImageW(NULL, wide, IMAGE_CURSOR, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE) : NULL;
    free(wide);
    if (cursor && custom_hotspot) {
        ICONINFO icon;
        if (GetIconInfo(cursor, &icon)) {
            BITMAP bitmap;
            int width = 1, height = 1;
            if (GetObjectW(icon.hbmColor ? icon.hbmColor : icon.hbmMask, sizeof(bitmap), &bitmap)) { width = bitmap.bmWidth; height = icon.hbmColor ? bitmap.bmHeight : bitmap.bmHeight / 2; }
            icon.xHotspot = (DWORD)fmaxf(0, fminf(x, (float)width - 1));
            icon.yHotspot = (DWORD)fmaxf(0, fminf(y, (float)height - 1));
            HCURSOR replacement = (HCURSOR)CreateIconIndirect(&icon);
            if (icon.hbmColor) DeleteObject(icon.hbmColor);
            if (icon.hbmMask) DeleteObject(icon.hbmMask);
            if (replacement) { DestroyCursor(cursor); cursor = replacement; }
        }
    }
    if (!cursor) cursor = image_cursor(path, (int)x, (int)y);
    CursorEntry *slot = &cursor_cache[cursor_next++ % 32];
    if (slot->handle) { if (GetCursor() == slot->handle) SetCursor(LoadCursorW(NULL, IDC_ARROW)); DestroyCursor(slot->handle); }
    free(slot->key); slot->key = key; slot->handle = cursor;
    return cursor;
}
static HCURSOR keyword_cursor(const char *keyword, int text, int pointer) {
    LPCWSTR id = IDC_ARROW;
    if (!strcmp(keyword, "none")) return NULL;
    if (!strcmp(keyword, "auto")) id = text ? IDC_IBEAM : pointer ? IDC_HAND : IDC_ARROW;
    else if (!strcmp(keyword, "pointer") || !strcmp(keyword, "grab") || !strcmp(keyword, "grabbing")) id = IDC_HAND;
    else if (!strcmp(keyword, "text") || !strcmp(keyword, "vertical-text")) id = IDC_IBEAM;
    else if (!strcmp(keyword, "wait")) id = IDC_WAIT;
    else if (!strcmp(keyword, "progress")) id = IDC_APPSTARTING;
    else if (!strcmp(keyword, "help")) id = IDC_HELP;
    else if (!strcmp(keyword, "not-allowed") || !strcmp(keyword, "no-drop")) id = IDC_NO;
    else if (!strcmp(keyword, "move") || !strcmp(keyword, "all-scroll")) id = IDC_SIZEALL;
    else if (!strcmp(keyword, "crosshair") || !strcmp(keyword, "cell") || !strcmp(keyword, "zoom-in") || !strcmp(keyword, "zoom-out")) id = IDC_CROSS;
    else if (!strcmp(keyword, "col-resize") || !strcmp(keyword, "e-resize") || !strcmp(keyword, "w-resize") || !strcmp(keyword, "ew-resize")) id = IDC_SIZEWE;
    else if (!strcmp(keyword, "row-resize") || !strcmp(keyword, "n-resize") || !strcmp(keyword, "s-resize") || !strcmp(keyword, "ns-resize")) id = IDC_SIZENS;
    else if (!strcmp(keyword, "ne-resize") || !strcmp(keyword, "sw-resize") || !strcmp(keyword, "nesw-resize")) id = IDC_SIZENESW;
    else if (!strcmp(keyword, "nw-resize") || !strcmp(keyword, "se-resize") || !strcmp(keyword, "nwse-resize")) id = IDC_SIZENWSE;
    // context-menu, alias and copy use arrow; Windows has no stock equivalent.
    return LoadCursorW(NULL, id);
}
void ui_cursor_update(const unsigned char *value, size_t length, int default_text, int default_pointer) {
    char *copy = copy_range((const char *)value, length);
    if (!copy) return;
    char *start = copy, *part = copy, quote = 0;
    int depth = 0;
    HCURSOR cursor = NULL;
    int resolved = 0;
    for (;;) {
        char ch = *part;
        if (quote) { if (ch == quote) quote = 0; }
        else if (ch == '\'' || ch == '"') quote = ch;
        else if (ch == '(') ++depth;
        else if (ch == ')' && depth) --depth;
        if (!ch || (ch == ',' && !depth && !quote)) {
            *part = 0;
            char *candidate = trim(start);
            if (!_strnicmp(candidate, "url(", 4)) { cursor = resource_cursor(candidate); if (cursor) { resolved = 1; break; } }
            else if (*candidate) { cursor = keyword_cursor(candidate, default_text, default_pointer); resolved = 1; }
            if (!ch) break;
            start = part + 1;
        }
        ++part;
    }
    if (!resolved) cursor = keyword_cursor("auto", default_text, default_pointer);
    SetCursor(cursor);
    free(copy);
}
void ui_cursor_shutdown(void) {
    SetCursor(LoadCursorW(NULL, IDC_ARROW));
    for (unsigned i = 0; i < 32; ++i) { if (cursor_cache[i].handle) DestroyCursor(cursor_cache[i].handle); free(cursor_cache[i].key); memset(&cursor_cache[i], 0, sizeof(cursor_cache[i])); }
    cursor_next = 0;
}
#else
void ui_cursor_update(const unsigned char *value, size_t length, int default_text, int default_pointer) { (void)value; (void)length; (void)default_text; (void)default_pointer; }
void ui_cursor_shutdown(void) {}
#endif
