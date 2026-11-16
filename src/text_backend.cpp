#include <wchar.h>
// Windows natural text layout and grayscale coverage through DirectWrite.
// The UTF-8 boundary is length-aware, including embedded NULs.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dwrite_2.h>
#include <string>
#include <vector>
#include <memory>
#include <algorithm>
#include <imm.h>
#include <stdint.h>
#include <stdlib.h>
#include <cmath>
#include <cctype>
#include <string.h>
#include <wctype.h>
#include <limits.h>
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
static int equals(const char *s,size_t n,const char *literal) { return n==strlen(literal) && _strnicmp(s,literal,n)==0; }
static WCHAR *wide(const char *s,size_t n,int *length) {
    if(n>INT_MAX) return NULL;
    *length=n?MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,(int)n,NULL,0):0;
    if(n && !*length) return NULL;
    WCHAR *out=(WCHAR*)calloc((size_t)*length+1,sizeof(WCHAR));
    if(out && n) MultiByteToWideChar(CP_UTF8,0,s,(int)n,out,*length);
    return out;
}
// Windows NLS supplies Unicode case mapping and locale-specific Turkish/Azeri I.
// Capitalization changes word initials only, preserving the remaining author case.
static WCHAR *transform_text(const WCHAR *text,int length,const TextStyle *s,int *out_length) {
    *out_length=length;
    if(!s || equals(s->transform,s->transform_length,"none") || !length) {
        WCHAR *out=(WCHAR*)malloc(((size_t)length+1)*sizeof(WCHAR));
        if(out) { memcpy(out,text,(size_t)length*sizeof(WCHAR)); out[length]=0; } return out;
    }
    int locale_length=0; WCHAR *locale=wide(s->language,s->language_length,&locale_length);
    const WCHAR *locale_name=locale && locale_length?locale:LOCALE_NAME_INVARIANT;
    if (equals(s->transform, s->transform_length, "uppercase")) {
        // Windows NLS uses a simple sharp-s mapping on some versions. CSS uses
        // the Unicode full uppercase expansion; map before NLS locale casing.
        std::wstring expanded;
        for(int i=0;i<length;++i) {
            if(text[i]==0x00df) expanded.append(L"ss");
            else expanded.push_back(text[i]);
        }
        int required = LCMapStringEx(locale_name, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, expanded.data(), (int)expanded.size(), NULL, 0, NULL, NULL, 0);
        WCHAR *out = required ? (WCHAR*)calloc((size_t)required + 1, sizeof(WCHAR)) : NULL;
        if (out && LCMapStringEx(locale_name, LCMAP_UPPERCASE | LCMAP_LINGUISTIC_CASING, expanded.data(), (int)expanded.size(), out, required, NULL, NULL, 0)) {
            *out_length = required; free(locale); return out;
        }
        free(out);
    } else if (equals(s->transform, s->transform_length, "lowercase")) {
        const WCHAR *eff_locale = (locale_name == LOCALE_NAME_INVARIANT && (wmemchr(text, 0x03a3, length))) ? L"el-GR" : locale_name;
        int required = LCMapStringEx(eff_locale, LCMAP_LOWERCASE | LCMAP_LINGUISTIC_CASING, text, length, NULL, 0, NULL, NULL, 0);
        WCHAR *out = required ? (WCHAR*)calloc((size_t)required + 1, sizeof(WCHAR)) : NULL;
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
        WCHAR *out=required?(WCHAR*)calloc((size_t)required+1,sizeof(WCHAR)):NULL;
        if(out && LCMapStringEx(locale_name,LCMAP_FULLWIDTH,text,length,out,required,NULL,NULL,0)) { *out_length=required; free(locale); return out; }
        free(out);
    } else if (equals(s->transform, s->transform_length, "capitalize")) {
        // A UTF-16 character can expand during uppercasing; size without a cap.
        size_t capacity = (size_t)length + 1, used = 0;
        WCHAR *out = (WCHAR*)malloc(capacity * sizeof(WCHAR));
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
                WCHAR *grown = (WCHAR*)realloc(out, next * sizeof(WCHAR));
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
    WCHAR *out = (WCHAR*)malloc(((size_t)length + 1) * sizeof(WCHAR));
    if (out) { memcpy(out, text, (size_t)length * sizeof(WCHAR)); out[length] = 0; }
    return out;
}
// All COM objects and cached layouts are UI-thread owned.
template<class T> struct Com {
    T *p = nullptr;
    ~Com() { if (p) p->Release(); }
    T **out() { return &p; }
    T *operator->() const { return p; }
};
struct Engine {
    Com<IDWriteFactory2> factory;
    Com<IDWriteFontCollection> fonts;
    Engine() {
        if (SUCCEEDED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory2), (IUnknown**)factory.out())))
            factory->GetSystemFontCollection(fonts.out(), TRUE);
    }
};
static Engine &engine() { static Engine e; return e; }
static std::wstring to_wide(const char *s, size_t n) {
    int len=0; WCHAR *p=wide(s,n,&len);
    std::wstring result=p?std::wstring(p,len):std::wstring(); free(p); return result;
}
static std::vector<std::wstring> families(const TextStyle *s) {
    std::vector<std::wstring> result;
    size_t pos=0;
    while (s && pos<s->family_length) {
        size_t start=pos; char quote=0;
        while(pos<s->family_length) {
            char c=s->family[pos];
            if(c=='\'' || c=='"') { if(!quote) quote=c; else if(quote==c) quote=0; }
            if(c==',' && !quote) break;
            ++pos;
        }
        size_t end=pos; if(pos<s->family_length) ++pos;
        while(start<end && isspace((unsigned char)s->family[start])) ++start;
        while(end>start && isspace((unsigned char)s->family[end-1])) --end;
        bool quoted=end>start+1 && (s->family[start]=='\'' || s->family[start]=='"') && s->family[end-1]==s->family[start];
        if(quoted) { ++start; --end; }
        const char *name=s->family+start; size_t n=end-start;
        std::wstring f=to_wide(name,n);
        if(!quoted) {
            if(equals(name,n,"system-ui") || equals(name,n,"sans-serif") || equals(name,n,"ui-sans-serif")) f=L"Segoe UI";
            else if(equals(name,n,"serif") || equals(name,n,"ui-serif")) f=L"Times New Roman";
            else if(equals(name,n,"monospace") || equals(name,n,"ui-monospace")) f=L"Consolas";
            else if(equals(name,n,"cursive")) f=L"Comic Sans MS";
            else if(equals(name,n,"fantasy")) f=L"Impact";
            else if(equals(name,n,"ui-rounded")) f=L"Arial Rounded MT Bold";
        }
        UINT32 index=0; BOOL exists=FALSE;
        engine().fonts->FindFamilyName(f.c_str(),&index,&exists);
        if(exists) result.push_back(f);
    }
    if(result.empty()) result.push_back(L"Segoe UI");
    return result;
}
struct Run {
    std::wstring original, text;
    Com<IDWriteTextLayout1> layout;
    TextMetrics metrics={};
};
static bool make_run(Run &r,const char *utf8,size_t length,float size,const TextStyle *s) {
    Engine &e=engine();
    if(!e.factory.p || !e.fonts.p || !std::isfinite(size) || size<=0 || size>4096) return false;
    r.original=to_wide(utf8,length);
    if(length && r.original.empty()) return false;
    int len=0; WCHAR *transformed=transform_text(r.original.data(),(int)r.original.size(),s,&len);
    if(!transformed) return false;
    r.text.assign(transformed,len); free(transformed);
    // DirectWrite handles TAB as a layout control before inline objects. A
    // zero-size CSS tab is a zero-width separator with the same UTF-16 index.
    if(s && s->tab_size<=0) for(auto &c:r.text) if(c==L'\t') c=0x200b;
    auto names=families(s);
    std::wstring locale=s?to_wide(s->language,s->language_length):L"";
    if(locale.empty()) locale=L"en-US";
    const DWRITE_FONT_STYLE style=!s || equals(s->style,s->style_length,"normal")?DWRITE_FONT_STYLE_NORMAL:
        equals(s->style,s->style_length,"italic")?DWRITE_FONT_STYLE_ITALIC:DWRITE_FONT_STYLE_OBLIQUE;
    Com<IDWriteTextFormat> format;
    if(FAILED(e.factory->CreateTextFormat(names[0].c_str(),e.fonts.p,
        (DWRITE_FONT_WEIGHT)(int)(s?std::clamp(s->weight,1.f,999.f):400.f),style,DWRITE_FONT_STRETCH_NORMAL,size,locale.c_str(),format.out()))) return false;
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    Com<IDWriteTextLayout> base;
    if(FAILED(e.factory->CreateTextLayout(r.text.data(),(UINT32)r.text.size(),format.p,1000000,1000000,base.out())) ||
       FAILED(base->QueryInterface(__uuidof(IDWriteTextLayout1),(void**)r.layout.out()))) return false;
    // CSS family order applies to missing glyphs too; retain the system fallback
    // after the author list for Indic, Arabic, CJK and emoji on this machine.
    Com<IDWriteTextLayout2> layout2;
    Com<IDWriteFontFallbackBuilder> builder;
    Com<IDWriteFontFallback> fallback,system;
    if(SUCCEEDED(base->QueryInterface(__uuidof(IDWriteTextLayout2),(void**)layout2.out())) &&
       SUCCEEDED(e.factory->CreateFontFallbackBuilder(builder.out()))) {
        std::vector<const WCHAR*> pointers;
        for(auto &n:names) pointers.push_back(n.c_str());
        DWRITE_UNICODE_RANGE range={0,0x10ffff};
        if(FAILED(builder->AddMapping(&range,1,pointers.data(),(UINT32)pointers.size(),e.fonts.p,nullptr,nullptr,1))) return false;
        if(SUCCEEDED(e.factory->GetSystemFontFallback(system.out()))) builder->AddMappings(system.p);
        if(SUCCEEDED(builder->CreateFontFallback(fallback.out()))) layout2->SetFontFallback(fallback.p);
    }
    const DWRITE_TEXT_RANGE all={0,(UINT32)r.text.size()};
    r.layout->SetPairKerning(TRUE,all);
    if(s) {
        if(FAILED(r.layout->SetCharacterSpacing(0,s->letter_spacing,0,all))) return false;
        for(UINT32 i=0;i<r.text.size();++i) if(r.text[i]==L' ' || r.text[i]==0xa0)
            r.layout->SetCharacterSpacing(0,s->letter_spacing+s->word_spacing,0,{i,1});
        Com<IDWriteTypography> typography;
        if(SUCCEEDED(e.factory->CreateTypography(typography.out()))) {
            // CSS: comma-separated quoted four-byte OpenType tags and on/off/integers.
            const char *p=s->feature_settings, *end=p+s->feature_settings_length;
            while(p<end) {
                while(p<end && (*p==',' || isspace((unsigned char)*p))) ++p;
                if(end-p<6 || (*p!='\'' && *p!='"')) break;
                char quote=*p++;
                UINT32 tag=DWRITE_MAKE_OPENTYPE_TAG(p[0],p[1],p[2],p[3]); p+=4;
                if(*p++!=quote) break;
                while(p<end && isspace((unsigned char)*p)) ++p;
                UINT32 value=1;
                if(end-p>=3 && !strncmp(p,"off",3)) { value=0; p+=3; }
                else if(end-p>=2 && !strncmp(p,"on",2)) p+=2;
                else if(p<end && isdigit((unsigned char)*p)) {
                    value=0;
                    while(p<end && isdigit((unsigned char)*p)) { value=std::min(value,100000u)*10+(*p++-'0'); }
                }
                typography->AddFontFeature({(DWRITE_FONT_FEATURE_TAG)tag,value});
                if(tag==DWRITE_MAKE_OPENTYPE_TAG('k','e','r','n')) r.layout->SetPairKerning(value!=0,all);
                while(p<end && *p!=',') ++p;
            }
            r.layout->SetTypography(typography.p,all);
        }
        // Tabs use the same styled space advance as measurement and painting.
        Com<IDWriteTextLayout> space;
        DWRITE_TEXT_METRICS sm={};
        if(SUCCEEDED(e.factory->CreateTextLayout(L" ",1,format.p,10000,10000,space.out()))) space->GetMetrics(&sm);
        float tab=s->tab_size_is_length?s->tab_size:s->tab_size*(sm.widthIncludingTrailingWhitespace+s->letter_spacing+s->word_spacing);
        // DirectWrite requires a positive stop. Zero-size tabs were converted
        // to zero-width separators before layout, retaining author indices.
        if(tab>0) r.layout->SetIncrementalTabStop(tab);
    }
    DWRITE_TEXT_METRICS m={}; DWRITE_LINE_METRICS line={}; UINT32 count=0;
    if(FAILED(r.layout->GetMetrics(&m))) return false;
    r.layout->GetLineMetrics(&line,1,&count);
    r.metrics.width=m.widthIncludingTrailingWhitespace;
    r.metrics.height=line.height;
    r.metrics.ascent=line.baseline;
    r.metrics.descent=std::max(0.f,line.height-line.baseline);
    r.metrics.leading=0;
    return true;
}
// Exact, length-delimited keys: hash collisions cannot reuse a different run.
// Retain the actual layout, not just metrics, for measure/paint/caret consistency.
struct Entry { std::string key; std::unique_ptr<Run> run; };
static std::vector<Entry> &runs() { static std::vector<Entry> cache; return cache; }
static Run *get_run(const char *text,size_t length,float size,const TextStyle *s) {
    std::string key;
    auto bytes=[&](const void *p,size_t n) { key.append((const char*)&n,sizeof(n)); if(n) key.append((const char*)p,n); };
    bytes(text,length); bytes(&size,sizeof(size));
    if(s) {
        bytes(s->family,s->family_length); bytes(s->style,s->style_length); bytes(s->language,s->language_length);
        bytes(s->transform,s->transform_length); bytes(s->feature_settings,s->feature_settings_length); bytes(s->orientation,s->orientation_length);
        bytes(&s->weight,sizeof(float)); bytes(&s->letter_spacing,sizeof(float)); bytes(&s->word_spacing,sizeof(float));
        bytes(&s->tab_size,sizeof(float)); bytes(&s->tab_size_is_length,sizeof(int));
    }
    auto &cache=runs();
    for(size_t i=0;i<cache.size();++i) if(cache[i].key==key) {
        if(i+1!=cache.size()) std::rotate(cache.begin()+i,cache.begin()+i+1,cache.end());
        return cache.back().run.get();
    }
    auto run=std::make_unique<Run>();
    if(!make_run(*run,text,length,size,s)) return nullptr;
    // Avoid retaining unbounded author text or layouts from changing counters.
    if(length>16384) { static std::unique_ptr<Run> large; large=std::move(run); return large.get(); }
    if(cache.size()>=256) cache.erase(cache.begin());
    cache.push_back({std::move(key),std::move(run)}); return cache.back().run.get();
}
extern "C" int ui_text_measure_styled(const char *text,size_t length,float size,const TextStyle *s,TextMetrics *out) {
    Run *r=get_run(text,length,size,s); if(!r) return 0; *out=r->metrics; return 1;
}
static UINT32 display_index(Run &r,size_t byte,const char *utf8,const TextStyle *s) {
    int original=0; WCHAR *prefix=wide(utf8,byte,&original); if(!prefix) return 0;
    int mapped=0; WCHAR *t=transform_text(prefix,original,s,&mapped); free(prefix); free(t);
    return std::min((UINT32)mapped,(UINT32)r.text.size());
}
extern "C" float ui_text_caret_styled(const char *text,size_t length,float size,size_t byte,const TextStyle *s) {
    Run *r=get_run(text,length,size,s); if(!r) return 0;
    UINT32 index=display_index(*r,std::min(byte,length),text,s);
    FLOAT x=0,y=0; DWRITE_HIT_TEST_METRICS m={};
    r->layout->HitTestTextPosition(index,FALSE,&x,&y,&m); return x;
}
struct TextRect { float x,y,width,height; };
extern "C" int ui_text_selection_styled(const char *text,size_t length,float size,size_t start,size_t end,
    const TextStyle *s,TextRect *rects,UINT32 capacity) {
    Run *r=get_run(text,length,size,s); if(!r) return -1;
    UINT32 from=display_index(*r,std::min(start,length),text,s),to=display_index(*r,std::min(end,length),text,s),count=0;
    if(to<from) std::swap(from,to);
    std::vector<DWRITE_HIT_TEST_METRICS> metrics(capacity);
    HRESULT hr=r->layout->HitTestTextRange(from,to-from,0,0,capacity?metrics.data():nullptr,capacity,&count);
    if(FAILED(hr) && hr!=E_NOT_SUFFICIENT_BUFFER) return -1;
    for(UINT32 i=0;i<std::min(count,capacity);++i) rects[i]={metrics[i].left,metrics[i].top,metrics[i].width,metrics[i].height};
    return (int)count;
}
extern "C" int ui_text_position_styled(const char *text,size_t length,float size,float x,const TextStyle *s) {
    Run *r=get_run(text,length,size,s); if(!r) return 0;
    BOOL trailing=FALSE,inside=FALSE; DWRITE_HIT_TEST_METRICS hit={};
    if(FAILED(r->layout->HitTestPoint(x,r->metrics.ascent,&trailing,&inside,&hit))) return 0;
    UINT32 index=hit.textPosition+(trailing?hit.length:0);
    int original=0;
    if(!s || equals(s->transform,s->transform_length,"none")) original=std::min(index,(UINT32)r->original.size());
    else for(int i=1;i<=(int)r->original.size();++i) {
        if(i<(int)r->original.size() && r->original[i-1]>=0xd800 && r->original[i-1]<=0xdbff) continue;
        int mapped=0; WCHAR *prefix=transform_text(r->original.data(),i,s,&mapped); free(prefix);
        if(mapped>(int)index) break; original=i;
    }
    return original?WideCharToMultiByte(CP_UTF8,0,r->original.data(),original,nullptr,0,nullptr,nullptr):0;
}
struct GlyphMask { RECT bounds; std::vector<BYTE> alpha; };
struct Raster : IDWriteTextRenderer {
    float scale,phase_x,phase_y;
    bool sideways;
    float line_height;
    RECT bounds={0,0,0,0};
    std::vector<GlyphMask> masks;
    UINT32 glyphs=0,missing=0,glyph_runs=0;
    Raster(float s,float x,float y,bool rotated=false,float height=0):scale(s),phase_x(x),phase_y(y),sideways(rotated),line_height(height) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void **out) override {
        if(iid==__uuidof(IUnknown) || iid==__uuidof(IDWritePixelSnapping) || iid==__uuidof(IDWriteTextRenderer)) {
            *out=static_cast<IDWriteTextRenderer*>(this); return S_OK;
        }
        *out=nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return 1; }
    ULONG STDMETHODCALLTYPE Release() override { return 1; }
    HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(void*,BOOL *disabled) override { *disabled=TRUE; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetCurrentTransform(void*,DWRITE_MATRIX *m) override { *m={1,0,0,1,0,0}; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPixelsPerDip(void*,FLOAT *s) override { *s=scale; return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawGlyphRun(void*,FLOAT x,FLOAT y,DWRITE_MEASURING_MODE,const DWRITE_GLYPH_RUN *run,const DWRITE_GLYPH_RUN_DESCRIPTION*,IUnknown*) override {
        ++glyph_runs; glyphs+=run->glyphCount;
        for(UINT32 i=0;i<run->glyphCount;++i) if(!run->glyphIndices[i]) ++missing;
        Com<IDWriteGlyphRunAnalysis> analysis;
        DWRITE_MATRIX matrix={scale,0,0,scale,phase_x,phase_y};
        if(sideways) matrix={0,scale,-scale,0,line_height*scale+phase_x,phase_y};
        HRESULT hr=engine().factory->CreateGlyphRunAnalysis(run,&matrix,DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC,
            DWRITE_MEASURING_MODE_NATURAL,DWRITE_GRID_FIT_MODE_DEFAULT,DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE,x,y,analysis.out());
        if(FAILED(hr)) return hr;
        GlyphMask mask;
        hr=analysis->GetAlphaTextureBounds(DWRITE_TEXTURE_ALIASED_1x1,&mask.bounds);
        if(FAILED(hr)) return hr;
        const RECT &b=mask.bounds;
        if(b.right<=b.left || b.bottom<=b.top) return S_OK;
        size_t count=(size_t)(b.right-b.left)*(b.bottom-b.top);
        if(count>64*1024*1024) return E_OUTOFMEMORY;
        mask.alpha.resize(count);
        hr=analysis->CreateAlphaTexture(DWRITE_TEXTURE_ALIASED_1x1,&b,mask.alpha.data(),(UINT32)count);
        if(FAILED(hr)) return hr;
        bounds.left=std::min(bounds.left,b.left); bounds.top=std::min(bounds.top,b.top);
        bounds.right=std::max(bounds.right,b.right); bounds.bottom=std::max(bounds.bottom,b.bottom);
        masks.push_back(std::move(mask)); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawUnderline(void*,FLOAT,FLOAT,const DWRITE_UNDERLINE*,IUnknown*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawStrikethrough(void*,FLOAT,FLOAT,const DWRITE_STRIKETHROUGH*,IUnknown*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawInlineObject(void*,FLOAT,FLOAT,IDWriteInlineObject*,BOOL,BOOL,IUnknown*) override { return S_OK; }
};
extern "C" int ui_text_inspect_styled(const char *text,size_t length,float size,const TextStyle *s,UINT32 *glyphs,UINT32 *missing,UINT32 *glyph_runs) {
    Run *r=get_run(text,length,size,s); if(!r) return 0;
    Raster raster(1,0,0);
    if(FAILED(r->layout->Draw(nullptr,&raster,0,0))) return 0;
    *glyphs=raster.glyphs; *missing=raster.missing; *glyph_runs=raster.glyph_runs; return 1;
}
// Straight white RGBA coverage; no RGB ClearType fringes on transparent layers.
// Bearings include negative overhangs. Phase is in physical pixels [0,1).
extern "C" unsigned char *ui_text_raster_styled(const char *text,size_t length,float size,const TextStyle *s,
    float scale,float phase_x,float phase_y,int *width,int *height,int *left,int *top) {
    if(!std::isfinite(scale) || scale<=0 || scale>8) return nullptr;
    Run *r=get_run(text,length,size,s); if(!r) return nullptr;
    Raster raster(scale,phase_x,phase_y,s && equals(s->orientation,s->orientation_length,"sideways"),r->metrics.height);
    if(FAILED(r->layout->Draw(nullptr,&raster,0,0))) return nullptr;
    const RECT &b=raster.bounds;
    *width=std::max(1L,b.right-b.left); *height=std::max(1L,b.bottom-b.top); *left=b.left; *top=b.top;
    size_t count=(size_t)*width * *height;
    if(count>16*1024*1024) return nullptr;
    auto *pixels=(unsigned char*)malloc(count*4); if(!pixels) return nullptr;
    for(size_t i=0;i<count;++i) { pixels[i*4]=pixels[i*4+1]=pixels[i*4+2]=255; pixels[i*4+3]=0; }
    for(auto &mask:raster.masks) {
        int w=mask.bounds.right-mask.bounds.left,h=mask.bounds.bottom-mask.bounds.top;
        for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
            size_t offset=((size_t)(y+mask.bounds.top-b.top)* *width+x+mask.bounds.left-b.left)*4+3;
            unsigned a=mask.alpha[(size_t)y*w+x], old=pixels[offset];
            pixels[offset]=(unsigned char)(a+(old*(255-a)+127)/255);
        }
    }
    return pixels;
}
extern "C" void ui_text_free(void *data) { free(data); }
static HWND font_window;
static WNDPROC font_previous;
static bool font_pending;
static LRESULT CALLBACK font_messages(HWND window,UINT message,WPARAM w,LPARAM l) {
    if(message==WM_FONTCHANGE) font_pending=true;
    return CallWindowProcW(font_previous,window,message,w,l);
}
extern "C" void ui_text_initialize_dpi() {
    // Before GLFW creates the HWND. Harmless if an embedding host already set it.
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
}
extern "C" void ui_text_watch_fonts(void *window) {
    font_window=(HWND)window;
    font_previous=(WNDPROC)SetWindowLongPtrW(font_window,GWLP_WNDPROC,(LONG_PTR)font_messages);
}
extern "C" void ui_text_unwatch_fonts() {
    if(font_window && font_previous) SetWindowLongPtrW(font_window,GWLP_WNDPROC,(LONG_PTR)font_previous);
    font_window=nullptr; font_previous=nullptr; font_pending=false;
}
extern "C" int ui_text_fonts_changed() { bool changed=font_pending; font_pending=false; return changed; }
extern "C" void ui_text_invalidate_fonts() {
    runs().clear();
    auto &e=engine(); if(e.fonts.p) { e.fonts.p->Release(); e.fonts.p=nullptr; }
    if(e.factory.p) e.factory->GetSystemFontCollection(e.fonts.out(),TRUE);
}
extern "C" void ui_text_ime_position(void *window,float logical_x,float logical_y) {
    HIMC im=ImmGetContext((HWND)window); if(!im) return;
    // The Zig caller supplies logical CSS coordinates; IMM uses client pixels.
    UINT dpi=GetDpiForWindow((HWND)window);
    float scale=dpi?dpi/96.f:1.f;
    int x=(int)std::round(logical_x*scale),y=(int)std::round(logical_y*scale);
    COMPOSITIONFORM composition={}; composition.dwStyle=CFS_POINT; composition.ptCurrentPos={x,y};
    ImmSetCompositionWindow(im,&composition);
    CANDIDATEFORM candidate={}; candidate.dwStyle=CFS_CANDIDATEPOS; candidate.ptCurrentPos={x,y};
    ImmSetCandidateWindow(im,&candidate); ImmReleaseContext((HWND)window,im);
}
