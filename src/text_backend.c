#include <wchar.h>
// Windows text shaping and font fallback through Uniscribe, shared by measure
// and paint. The UTF-8 boundary is length-aware, including embedded NULs.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <usp10.h>
#include <imm.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <wctype.h>
typedef struct { float width,height,ascent,descent,leading; } TextMetrics;
typedef struct {
    const char *family; size_t family_length;
    const char *style; size_t style_length;
    const char *language; size_t language_length;
    const char *transform; size_t transform_length;
    const char *feature_settings; size_t feature_settings_length;
    const char *orientation; size_t orientation_length;
    float weight,letter_spacing,word_spacing,tab_size;
    int tab_size_is_length;
} TextStyle;
typedef struct { HDC dc; HFONT font; HGDIOBJ previous; WCHAR *text,*original; int length,original_length; SCRIPT_STRING_ANALYSIS analysis; } TextRun;
static int equals(const char *s,size_t n,const char *literal) { return n==strlen(literal) && _strnicmp(s,literal,n)==0; }
static WCHAR *wide(const char *s,size_t n,int *length) {
    if(n>INT_MAX) return NULL;
    *length=n?MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,(int)n,NULL,0):0;
    if(n && !*length) return NULL;
    WCHAR *out=calloc((size_t)*length+1,sizeof(WCHAR));
    if(out && n) MultiByteToWideChar(CP_UTF8,0,s,(int)n,out,*length);
    return out;
}
static int CALLBACK found_font(const LOGFONTW *lf,const TEXTMETRICW *tm,DWORD type,LPARAM found) {
    (void)lf;(void)tm;(void)type; *(int*)found=1; return 0;
}
static void choose_family(HDC dc,const TextStyle *s,WCHAR face[LF_FACESIZE]) {
    wcscpy(face,L"Segoe UI");
    if(!s) return;
    size_t pos=0;
    while(pos<s->family_length) {
        size_t start=pos; char quote=0;
        while(pos<s->family_length) { char c=s->family[pos]; if(c=='\'' || c=='"') { if(!quote) quote=c; else if(quote==c) quote=0; } if(c==',' && !quote) break; ++pos; }
        size_t end=pos; if(pos<s->family_length) ++pos;
        while(start<end && (s->family[start]==' ' || s->family[start]=='\t')) ++start;
        while(end>start && (s->family[end-1]==' ' || s->family[end-1]=='\t')) --end;
        int quoted=end>start+1 && (s->family[start]=='\'' || s->family[start]=='"') && s->family[end-1]==s->family[start];
        if(quoted) { ++start; --end; }
        const char *name=s->family+start; size_t n=end-start;
        const WCHAR *generic=NULL;
        if(!quoted) {
            if(equals(name,n,"system-ui") || equals(name,n,"sans-serif") || equals(name,n,"ui-sans-serif")) generic=L"Segoe UI";
            else if(equals(name,n,"serif") || equals(name,n,"ui-serif")) generic=L"Times New Roman";
            else if(equals(name,n,"monospace") || equals(name,n,"ui-monospace")) generic=L"Consolas";
            else if(equals(name,n,"cursive")) generic=L"Comic Sans MS";
            else if(equals(name,n,"fantasy")) generic=L"Impact";
            else if(equals(name,n,"ui-rounded")) generic=L"Arial Rounded MT Bold";
        }
        if(generic) { wcscpy(face,generic); return; }
        LOGFONTW query={0}; int length=0; WCHAR *candidate=wide(name,n,&length);
        if(!candidate) continue;
        if(length>0 && length<LF_FACESIZE) {
            memcpy(query.lfFaceName,candidate,(size_t)length*sizeof(WCHAR)); query.lfCharSet=DEFAULT_CHARSET;
            int found=0; EnumFontFamiliesExW(dc,&query,found_font,(LPARAM)&found,0);
            if(found) { wcscpy(face,candidate); free(candidate); return; }
        }
        free(candidate);
    }
}
// Windows NLS supplies Unicode case mapping and locale-specific Turkish/Azeri I.
// Capitalization changes word initials only, preserving the remaining author case.
static WCHAR *transform_text(const WCHAR *text,int length,const TextStyle *s,int *out_length) {
    *out_length=length;
    if(!s || equals(s->transform,s->transform_length,"none") || !length) {
        WCHAR *out=malloc(((size_t)length+1)*sizeof(WCHAR));
        if(out) { memcpy(out,text,(size_t)length*sizeof(WCHAR)); out[length]=0; } return out;
    }
    int locale_length=0; WCHAR *locale=wide(s->language,s->language_length,&locale_length);
    const WCHAR *locale_name=locale && locale_length?locale:LOCALE_NAME_INVARIANT;
    if (equals(s->transform, s->transform_length, "uppercase")) {
        const WCHAR *eff_locale = (locale_name == LOCALE_NAME_INVARIANT && wmemchr(text, 0x00df, length)) ? L"de-DE" : locale_name;
        int required = LCMapStringEx(eff_locale, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, text, length, NULL, 0, NULL, NULL, 0);
        WCHAR *out = required ? calloc((size_t)required + 1, sizeof(WCHAR)) : NULL;
        if (out && LCMapStringEx(eff_locale, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, text, length, out, required, NULL, NULL, 0)) {
            *out_length = required; free(locale); return out;
        }
        free(out);
    } else if (equals(s->transform, s->transform_length, "lowercase")) {
        const WCHAR *eff_locale = (locale_name == LOCALE_NAME_INVARIANT && (wmemchr(text, 0x03a3, length))) ? L"el-GR" : locale_name;
        int required = LCMapStringEx(eff_locale, LCMAP_LOWERCASE | LCMAP_LINGUISTIC_CASING, text, length, NULL, 0, NULL, NULL, 0);
        WCHAR *out = required ? calloc((size_t)required + 1, sizeof(WCHAR)) : NULL;
        if (out && LCMapStringEx(eff_locale, LCMAP_LOWERCASE | LCMAP_LINGUISTIC_CASING, text, length, out, required, NULL, NULL, 0)) {
            for (int i = 0; i < required; i++) {
                if (out[i] == 0x03c3) {
                    int is_end = (i + 1 == required) || iswspace(out[i + 1]) || iswpunct(out[i + 1]);
                    if (is_end) out[i] = 0x03c2;
                }
            }
            *out_length = required; free(locale); return out;
        }
        free(out);
    } else if (equals(s->transform, s->transform_length, "full-width")) {
        int required=LCMapStringEx(locale_name,LCMAP_FULLWIDTH,text,length,NULL,0,NULL,NULL,0);
        WCHAR *out=required?calloc((size_t)required+1,sizeof(WCHAR)):NULL;
        if(out && LCMapStringEx(locale_name,LCMAP_FULLWIDTH,text,length,out,required,NULL,NULL,0)) { *out_length=required; free(locale); return out; }
        free(out);
    } else if (equals(s->transform, s->transform_length, "capitalize")) {
        // A UTF-16 character can expand during uppercasing; size without a cap.
        size_t capacity = (size_t)length + 1, used = 0;
        WCHAR *out = malloc(capacity * sizeof(WCHAR));
        int initial = 1;
        if (!out) { free(locale); return NULL; }
        for (int i = 0; i < length;) {
            int count = (text[i] >= 0xd800 && text[i] <= 0xdbff && i + 1 < length) ? 2 : 1;
            WORD kind = 0;
            GetStringTypeW(CT_CTYPE1, text + i, 1, &kind);
            int required = initial && (kind & C1_ALPHA) ? LCMapStringEx(locale_name, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, text + i, count, NULL, 0, NULL, NULL, 0) : 0;
            size_t added = required > 0 ? (size_t)required : (size_t)count;
            if (used + added > INT_MAX) { free(out); free(locale); return NULL; }
            if (used + added + 1 > capacity) {
                size_t next = used + added + 1;
                WCHAR *grown = realloc(out, next * sizeof(WCHAR));
                if (!grown) { free(out); free(locale); return NULL; }
                out = grown; capacity = next;
            }
            if (required) LCMapStringEx(locale_name, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, text + i, count, out + used, required, NULL, NULL, 0);
            else memcpy(out + used, text + i, (size_t)count * sizeof(WCHAR));
            used += added;
            if (kind & (C1_ALPHA | C1_DIGIT)) initial = 0;
            else if (kind & (C1_SPACE | C1_PUNCT)) initial = 1;
            i += count;
        }
        out[used] = 0; *out_length = (int)used; free(locale); return out;
    }
    free(locale);
    WCHAR *out = malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (out) { memcpy(out, text, (size_t)length * sizeof(WCHAR)); out[length] = 0; }
    return out;
}
static void release_run(TextRun *r) {
    if (r->analysis) ScriptStringFree(&r->analysis);
    if (r->previous) SelectObject(r->dc, r->previous);
    if (r->font) DeleteObject(r->font);
    if (r->dc) DeleteDC(r->dc);
    free(r->text);
    free(r->original);
}
static int create_run(TextRun *r, const char *utf8, size_t length, float size, const TextStyle *s) {
    r->original = wide(utf8, length, &r->original_length);
    if (!r->original || !r->original_length) return 0;
    r->text = transform_text(r->original, r->original_length, s, &r->length);
    if (!r->text || !r->length) return 0;
    r->dc = CreateCompatibleDC(NULL);
    if (!r->dc) return 0;
    WCHAR face[LF_FACESIZE];
    choose_family(r->dc, s, face);
    int weight = s ? (int)fmax(1, fmin(1000, round(s->weight))) : FW_NORMAL;
    int italic = s && !equals(s->style, s->style_length, "normal");
    int escapement = 0, orientation_angle = 0;
    if (s && equals(s->orientation, s->orientation_length, "sideways")) {
        escapement = 2700;
        orientation_angle = 2700;
    }
    r->font = CreateFontW(-(int)fmax(1, round(size)), 0, escapement, orientation_angle, weight, italic, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY, DEFAULT_PITCH, face);
    if(!r->dc || !r->font) return 0;
    r->previous=SelectObject(r->dc,r->font);
    DWORD flags=SSA_GLYPHS|SSA_FALLBACK|SSA_LINK|SSA_BREAK;
    if(FAILED(ScriptStringAnalyse(r->dc,r->text,r->length,0,-1,flags,0,NULL,NULL,NULL,NULL,NULL,&r->analysis))) return 0;
    if(s && (s->letter_spacing!=0 || s->word_spacing!=0 || wmemchr(r->text,L'\t',r->length))) {
        int *dx=malloc((size_t)r->length*sizeof(int)); if(!dx) return 0;
        if(FAILED(ScriptStringGetLogicalWidths(r->analysis,dx))) {free(dx);return 0;}
        const SCRIPT_LOGATTR *attrs=ScriptString_pLogAttr(r->analysis);
        SIZE space={0}; GetTextExtentPoint32W(r->dc,L" ",1,&space);
        double tab=s->tab_size_is_length?s->tab_size:s->tab_size*(space.cx+s->letter_spacing+s->word_spacing);
        double desired=0; int rounded=0;
        for(int i=0;i<r->length;i++) {
            double advance=dx[i];
            if(r->text[i]==L'\t') advance=tab>0?tab-fmod(desired,tab):0;
            else {
                if(i+1==r->length || !attrs || attrs[i+1].fCharStop) advance+=s->letter_spacing;
                if(r->text[i]==L' ' || r->text[i]==0xa0) advance+=s->word_spacing;
            }
            desired+=fmax(0,advance); int next=(int)round(desired); dx[i]=next-rounded; rounded=next;
        }
        ScriptStringFree(&r->analysis);
        HRESULT result=ScriptStringAnalyse(r->dc,r->text,r->length,0,-1,flags,0,NULL,NULL,dx,NULL,NULL,&r->analysis);
        free(dx); if(FAILED(result)) return 0;
    }
    return 1;
}
int ui_text_measure_styled(const char *text,size_t length,float size,const TextStyle *style,TextMetrics *out) {
    TextRun r={0};
    if(!create_run(&r,text,length,size,style)) {release_run(&r); return 0;}
    TEXTMETRICW m; GetTextMetricsW(r.dc,&m);
    const SIZE *extent=ScriptString_pSize(r.analysis);
    out->width=(float)extent->cx;
    out->ascent=(float)m.tmAscent; out->descent=(float)m.tmDescent; out->leading=(float)m.tmExternalLeading;
    out->height=(float)(m.tmHeight+m.tmExternalLeading);
    release_run(&r); return 1;
}
// Caller owns the returned RGBA bitmap, released by ui_text_free.
unsigned char *ui_text_raster_styled(const char *text,size_t length,float size,const TextStyle *style,int *width,int *height) {
    TextRun r={0}; if(!create_run(&r,text,length,size,style)) {release_run(&r); return NULL;}
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
int ui_text_position_styled(const char *text,size_t length,float size,float x,const TextStyle *style) {
    TextRun r={0}; if(!create_run(&r,text,length,size,style)) {release_run(&r); return 0;}
    int cp=0,trailing=0; ScriptStringXtoCP(r.analysis,(int)round(x),&cp,&trailing);
    int utf16=cp+trailing; if(utf16<0) utf16=0; if(utf16>r.length) utf16=r.length;
    int original=utf16;
    if(style && !equals(style->transform,style->transform_length,"none")) {
        original=0;
        // Map display boundaries back to author UTF-8, including case expansions.
        for(int i=1;i<=r.original_length;i++) {
            if(i<r.original_length && r.original[i-1]>=0xd800 && r.original[i-1]<=0xdbff) continue;
            int mapped=0; WCHAR *prefix=transform_text(r.original,i,style,&mapped); free(prefix);
            if(mapped>utf16) break; original=i;
        }
    }
    int bytes=original?WideCharToMultiByte(CP_UTF8,0,r.original,original,NULL,0,NULL,NULL):0;
    release_run(&r); return bytes;
}
int ui_text_measure(const char *text,size_t length,float size,TextMetrics *out) {return ui_text_measure_styled(text,length,size,NULL,out);}
unsigned char *ui_text_raster(const char *text,size_t length,float size,int *width,int *height) {return ui_text_raster_styled(text,length,size,NULL,width,height);}
int ui_text_position(const char *text,size_t length,float size,float x) {return ui_text_position_styled(text,length,size,x,NULL);}
void ui_text_ime_position(void *window,int x,int y) {
    HIMC im=ImmGetContext((HWND)window); if(!im) return;
    COMPOSITIONFORM composition={0}; composition.dwStyle=CFS_POINT; composition.ptCurrentPos.x=x; composition.ptCurrentPos.y=y;
    ImmSetCompositionWindow(im,&composition);
    CANDIDATEFORM candidate={0}; candidate.dwStyle=CFS_CANDIDATEPOS; candidate.ptCurrentPos.x=x; candidate.ptCurrentPos.y=y;
    ImmSetCandidateWindow(im,&candidate); ImmReleaseContext((HWND)window,im);
}
