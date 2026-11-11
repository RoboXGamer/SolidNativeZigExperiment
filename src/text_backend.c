// Windows text shaping and font fallback through Uniscribe, shared by measure
// and paint. The UTF-8 boundary is length-aware, including embedded NULs.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <usp10.h>
#include <imm.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
typedef struct { float width,height,ascent,descent,leading; } TextMetrics;
typedef struct { HDC dc; HFONT font; HGDIOBJ previous; WCHAR *text; int length; SCRIPT_STRING_ANALYSIS analysis; } TextRun;
static void release_run(TextRun *r) {
    if(r->analysis) ScriptStringFree(&r->analysis);
    if(r->previous) SelectObject(r->dc,r->previous);
    if(r->font) DeleteObject(r->font);
    if(r->dc) DeleteDC(r->dc);
    free(r->text);
}
static int create_run(TextRun *r,const char *utf8,size_t length,float size) {
    if(length>INT_MAX) return 0;
    r->length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,utf8,(int)length,NULL,0);
    if(!r->length) return 0;
    r->text=(WCHAR*)malloc((size_t)r->length*sizeof(WCHAR));
    if(!r->text) return 0;
    MultiByteToWideChar(CP_UTF8,0,utf8,(int)length,r->text,r->length);
    r->dc=CreateCompatibleDC(NULL);
    r->font=CreateFontW(-(int)fmax(1,round(size)),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    if(!r->dc || !r->font) return 0;
    r->previous=SelectObject(r->dc,r->font);
    return SUCCEEDED(ScriptStringAnalyse(r->dc,r->text,r->length,0,-1,SSA_GLYPHS|SSA_FALLBACK|SSA_LINK,0,NULL,NULL,NULL,NULL,NULL,&r->analysis));
}
int ui_text_measure(const char *text,size_t length,float size,TextMetrics *out) {
    TextRun r={0};
    if(!create_run(&r,text,length,size)) {release_run(&r); return 0;}
    TEXTMETRICW m; GetTextMetricsW(r.dc,&m);
    const SIZE *extent=ScriptString_pSize(r.analysis);
    out->width=(float)extent->cx;
    out->ascent=(float)m.tmAscent; out->descent=(float)m.tmDescent; out->leading=(float)m.tmExternalLeading;
    out->height=(float)(m.tmHeight+m.tmExternalLeading);
    release_run(&r); return 1;
}
// Caller owns the returned RGBA bitmap, released by ui_text_free.
unsigned char *ui_text_raster(const char *text,size_t length,float size,int *width,int *height) {
    TextRun r={0}; if(!create_run(&r,text,length,size)) {release_run(&r); return NULL;}
    const SIZE *extent=ScriptString_pSize(r.analysis);
    *width=extent->cx>0?extent->cx:1; *height=extent->cy>0?extent->cy:1;
    BITMAPINFO info={0}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=*width;
    info.bmiHeader.biHeight=-*height; info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
    void *bits=NULL; HBITMAP bitmap=CreateDIBSection(r.dc,&info,DIB_RGB_COLORS,&bits,NULL,0);
    if(!bitmap) {release_run(&r); return NULL;}
    HGDIOBJ old=SelectObject(r.dc,bitmap);
    SetBkColor(r.dc,RGB(0,0,0)); SetTextColor(r.dc,RGB(255,255,255)); SetBkMode(r.dc,TRANSPARENT);
    memset(bits,0,(size_t)*width * *height * 4);
    ScriptStringOut(r.analysis,0,0,0,NULL,0,0,FALSE); GdiFlush();
    size_t count=(size_t)*width * *height;
    unsigned char *rgba=(unsigned char*)malloc(count*4);
    if(rgba) for(size_t i=0;i<count;i++) {
        unsigned char *pixel=(unsigned char*)bits+i*4;
        rgba[i*4]=rgba[i*4+1]=rgba[i*4+2]=255;
        rgba[i*4+3]=(unsigned char)(((int)pixel[0]+pixel[1]+pixel[2])/3);
    }
    SelectObject(r.dc,old); DeleteObject(bitmap); release_run(&r); return rgba;
}
void ui_text_free(void *data) {free(data);}
int ui_text_position(const char *text,size_t length,float size,float x) {
    TextRun r={0}; if(!create_run(&r,text,length,size)) {release_run(&r); return 0;}
    int cp=0,trailing=0; ScriptStringXtoCP(r.analysis,(int)round(x),&cp,&trailing);
    int utf16=cp+trailing; if(utf16<0) utf16=0; if(utf16>r.length) utf16=r.length;
    int bytes=utf16?WideCharToMultiByte(CP_UTF8,0,r.text,utf16,NULL,0,NULL,NULL):0;
    release_run(&r); return bytes;
}
void ui_text_ime_position(void *window,int x,int y) {
    HIMC im=ImmGetContext((HWND)window); if(!im) return;
    COMPOSITIONFORM composition={0}; composition.dwStyle=CFS_POINT; composition.ptCurrentPos.x=x; composition.ptCurrentPos.y=y;
    ImmSetCompositionWindow(im,&composition);
    CANDIDATEFORM candidate={0}; candidate.dwStyle=CFS_CANDIDATEPOS; candidate.ptCurrentPos.x=x; candidate.ptCurrentPos.y=y;
    ImmSetCandidateWindow(im,&candidate); ImmReleaseContext((HWND)window,im);
}
