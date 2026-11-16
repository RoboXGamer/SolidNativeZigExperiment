#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>
#include <GLFW/glfw3.h>
#include <thorvg.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>
static decltype(&glFinish) gFinish;
static decltype(&glReadPixels) gReadPixels;
static decltype(&glGetString) gGetString;
static decltype(&glGenTextures) gGenTextures;
static decltype(&glBindTexture) gBindTexture;
static decltype(&glTexImage2D) gTexImage2D;
static decltype(&glTexSubImage2D) gTexSubImage2D;
static decltype(&glDeleteTextures) gDeleteTextures;
using namespace tvg;
using Clock = std::chrono::steady_clock;
static void check(Result r) { if(r != Result::Success) { fprintf(stderr,"ThorVG result %d\n",int(r)); exit(2); } }
static void hr(HRESULT r) { if(FAILED(r)) { fprintf(stderr,"HRESULT %lx\n",(unsigned long)r); exit(3); } }
static double elapsed(Clock::time_point t) { return std::chrono::duration<double,std::milli>(Clock::now()-t).count(); }
static unsigned paints=0;
static Shape* rect(float x,float y,float w,float h,int r,int g,int b,float radius=0) {
    auto s=Shape::gen(); ++paints; check(s->appendRect(x,y,w,h,radius,radius)); check(s->fill(r,g,b)); return s;
}
static Scene* scene() { ++paints; return Scene::gen(); }

// Real DirectWrite shaping/fallback and Direct2D grayscale antialiasing into a
// bounded WIC bitmap. This buffer is immutable; ThorVG owns a copied Picture.
static Picture* modernText(float rasterScale=1) {
    IDWriteFactory* dw=nullptr; ID2D1Factory* d2=nullptr; IWICImagingFactory* wi=nullptr;
    hr(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),(IUnknown**)&dw));
    hr(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,&d2));
    hr(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&wi)));
    unsigned width=unsigned(600*rasterScale),height=unsigned(100*rasterScale);
    IWICBitmap* bitmap=nullptr; hr(wi->CreateBitmap(width,height,GUID_WICPixelFormat32bppPBGRA,WICBitmapCacheOnLoad,&bitmap));
    ID2D1RenderTarget* rt=nullptr;
    auto props=D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,D2D1_ALPHA_MODE_PREMULTIPLIED),96*rasterScale,96*rasterScale);
    hr(d2->CreateWicBitmapRenderTarget(bitmap,props,&rt));
    IDWriteTextFormat* fmt=nullptr; hr(dw->CreateTextFormat(L"Segoe UI",nullptr,DWRITE_FONT_WEIGHT_NORMAL,DWRITE_FONT_STYLE_NORMAL,DWRITE_FONT_STRETCH_NORMAL,21.5f,L"en-us",&fmt));
    const wchar_t* str=L"ThorVG retained UI\nDirectWrite: office  \u0627\u0644\u0639\u0631\u0628\u064a\u0629  \u0928\u092e\u0938\u094d\u0924\u0947";
    IDWriteTextLayout* layout=nullptr; hr(dw->CreateTextLayout(str,(UINT32)wcslen(str),fmt,600,100,&layout));
    DWRITE_TEXT_METRICS metrics{}; hr(layout->GetMetrics(&metrics));
    printf("DirectWrite layout %.3f x %.3f; %u lines\n",metrics.width,metrics.height,metrics.lineCount);
    ID2D1SolidColorBrush* brush=nullptr; hr(rt->CreateSolidColorBrush(D2D1::ColorF(0.91f,0.93f,0.96f),&brush));
    rt->BeginDraw(); rt->Clear(D2D1::ColorF(0,0)); rt->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    rt->DrawTextLayout(D2D1::Point2F(0.25f,0.25f),layout,brush); hr(rt->EndDraw());
    std::vector<uint32_t> data(width*height); hr(bitmap->CopyPixels(nullptr,width*4,(UINT)data.size()*4,(BYTE*)data.data()));
    for(auto& p:data) p=(p&0xff00ff00)|((p&255)<<16)|((p>>16)&255);
    auto pic=Picture::gen(); ++paints; check(pic->load(data.data(),width,height,ColorSpace::ABGR8888,true)); check(pic->size(600,100)); check(pic->translate(36,20));
    brush->Release(); layout->Release(); fmt->Release(); rt->Release(); bitmap->Release(); wi->Release(); d2->Release(); dw->Release(); return pic;
}
struct UI {
    Scene* root=nullptr; Shape* moving=nullptr; Picture* textPicture=nullptr; std::vector<Shape*> tiles; unsigned count=0;
    UI(Canvas* c,int boards,bool text=true,int shadowMode=1,float rasterScale=1) {
        paints=0; root=scene(); check(root->add(rect(0,0,800,600,19,25,37)));
        if(text) { textPicture=modernText(rasterScale);check(root->add(textPicture)); }
        auto board=scene(); auto shadow=scene();
        check(shadow->add(rect(20,20,334,334,39,49,66,22)));
        check(shadow->add(SceneEffect::DropShadow,0,0,0,160,90.0,8.0,6.0,50));
        if(shadowMode==2) {
            unsigned saved=paints; std::vector<uint32_t> pixels(380*380);
            auto scratch=SwCanvas::gen(EngineOption::None);
            check(scratch->target(pixels.data(),380,380,380,ColorSpace::ABGR8888));
            check(scratch->add(shadow)); check(scratch->update()); check(scratch->draw(true)); check(scratch->sync());
            auto cached=Picture::gen(); check(cached->load(pixels.data(),380,380,ColorSpace::ABGR8888,true));
            delete scratch; paints=saved-1; check(cached->translate(18,110)); check(board->add(cached));
        } else {
            if(shadowMode==1)check(shadow->clip(rect(18,110,380,380,0,0,0)));
            check(shadow->translate(18,110)); check(board->add(shadow));
        }
        for(int n=0;n<boards;n++) {
            auto group=scene(); const float sc=boards==1?1.0f:0.115f;
            for(int i=0;i<9;i++) {
                float x=50+(i%3)*104,y=142+(i/3)*104;
                auto tile=rect(x,y,94,94,48,61,80,12); check(group->add(tile)); tiles.push_back(tile);
                if(i%3==0) { auto mark=Shape::gen(); ++paints; check(mark->moveTo(x+27,y+27)); check(mark->lineTo(x+67,y+67)); check(mark->moveTo(x+67,y+27)); check(mark->lineTo(x+27,y+67)); check(mark->strokeWidth(9)); check(mark->strokeFill(93,211,191)); check(mark->strokeCap(StrokeCap::Round)); check(group->add(mark)); }
                if(i%3==1) { auto mark=Shape::gen(); ++paints; check(mark->appendCircle(x+47,y+47,25,25)); check(mark->strokeWidth(9)); check(mark->strokeFill(240,175,96)); check(group->add(mark)); }
            }
            if(boards!=1) { check(group->scale(sc)); check(group->translate(40+(n%8)*46,125+(n/8)*46)); }
            check(board->add(group));
        }
        check(root->add(board));
        // Nested clips: outer scene circle -> inner scene rectangle.
        auto outer=scene(); auto inner=scene(); auto fill=rect(410,140,160,100,87,185,224);
        check(fill->clip(rect(430,150,100,80,0,0,0,10))); check(inner->add(fill));
        auto circle=Shape::gen(); ++paints; check(circle->appendCircle(490,190,43,43)); check(inner->clip(circle)); check(outer->add(inner)); check(root->add(outer));
        // Two overlapping opaque children at group opacity 128. Overlap must
        // have the same opacity as the second child by itself.
        auto opacity=scene(); check(opacity->add(rect(420,280,90,70,240,80,60)));
        check(opacity->add(rect(460,300,90,70,60,120,240))); check(opacity->opacity(128)); check(root->add(opacity));
        moving=rect(610,160,52,52,180,120,230,9); check(moving->rotate(12)); check(moving->translate(48,-120)); check(root->add(moving));
        // Ordered overlap sentinel, stable interior test at (670,420).
        check(root->add(rect(600,390,100,80,230,80,60))); check(root->add(rect(650,410,100,80,70,210,130,8)));
        if(text) {
            check(Text::load("C:/Windows/Fonts/segoeui.ttf")); auto t=Text::gen(); ++paints;
            check(t->font("segoeui")); check(t->size(13.5f)); check(t->text("ThorVG native TTF: vector text")); check(t->fill(180,195,210)); check(t->translate(38,535)); check(root->add(t));
        }
        count=paints; check(c->add(root));
    }
    void color(int i,bool all) { for(size_t k=0;k<(all?tiles.size():1);k++) check(tiles[k]->fill(i%2?70:48,i%2?95:61,i%2?130:80)); }
    void geometry(int i) { check(tiles[0]->reset()); check(tiles[0]->appendRect(50,142,i%2?82:94,94,12,12)); }
    void dpi(float scale) { check(root->scale(scale)); if(textPicture) { check(root->remove(textPicture)); textPicture=modernText(scale);check(root->add(textPicture)); } }
};
struct Target {
    bool gpu; int w,h; Canvas* c; std::vector<uint32_t> data;
    Target(bool gl,bool smart,int width,int height):gpu(gl),w(width),h(height),data(w*h) {
        c=gl?(Canvas*)GlCanvas::gen(smart?EngineOption::SmartRender:EngineOption::None):(Canvas*)SwCanvas::gen(smart?EngineOption::SmartRender:EngineOption::None);
        if(!c) { fprintf(stderr,"Canvas unavailable\n"); exit(4); } target();
    }
    void target() {
        if(gpu) check(((GlCanvas*)c)->target(nullptr,nullptr,wglGetCurrentContext(),0,w,h,ColorSpace::ABGR8888S));
        else check(((SwCanvas*)c)->target(data.data(),w,w,h,ColorSpace::ABGR8888));
    }
    ~Target(){ delete c; }
    double frame(bool clear=false,uint64_t* damage=nullptr) {
        auto t=Clock::now(); check(c->update()); check(c->draw(clear||gpu));
        if(damage) { auto cnt=c->dirtyRegions(); std::vector<Region> r(cnt); if(cnt)check(c->dirtyRegions(r.data(),cnt)); *damage=0; for(auto x:r)*damage+=uint64_t(x.xMax-x.xMin)*(x.yMax-x.yMin); }
        check(c->sync()); if(gpu) gFinish(); return elapsed(t);
    }
    std::vector<uint32_t> pixels() {
        if(!gpu)return data;
        gReadPixels(0,0,w,h,GL_RGBA,GL_UNSIGNED_BYTE,data.data()); std::vector<uint32_t> out(w*h);
        for(int y=0;y<h;y++) std::copy_n(data.data()+(h-1-y)*w,w,out.data()+y*w); return out;
    }
};
static void ppm(const std::string& file,const std::vector<uint32_t>& p,int w,int h) {
    std::ofstream o(file,std::ios::binary); o<<"P6\n"<<w<<" "<<h<<"\n255\n"; for(auto c:p){char b[3]={char(c),char(c>>8),char(c>>16)};o.write(b,3);}
}
static int failures=0;
static void assertion(bool pass,const char* what) { printf("%s %s\n",pass?"PASS":"FAIL",what); if(!pass)++failures; }
static bool pixelNear(uint32_t p,int r,int g,int b,int tolerance=3) { return abs(int(p&255)-r)<=tolerance&&abs(int((p>>8)&255)-g)<=tolerance&&abs(int((p>>16)&255)-b)<=tolerance; }
static void glClearDiagnostic() {
    Target t(true,false,1280,800);UI ui(t.c,1,false,2);check(ui.root->scale(1.333333f));t.frame(true);
    auto good=t.pixels();
    // Deliberately bypass Target::frame's required GL clear to demonstrate
    // why a fully redrawn transparent GPU target cannot preserve old pixels.
    check(t.c->update());check(t.c->draw(false));check(t.c->sync());gFinish();auto bad=t.pixels();
    int count=0,xmin=1280,ymin=800,xmax=0,ymax=0;
    for(int y=0;y<800;y++)for(int x=0;x<1280;x++)if(good[y*1280+x]!=bad[y*1280+x]){++count;xmin=std::min(xmin,x);ymin=std::min(ymin,y);xmax=std::max(xmax,x);ymax=std::max(ymax,y);}
    printf("GL no-clear diagnostic differing pixels=%d bbox=(%d,%d)-(%d,%d)\n",count,xmin,ymin,xmax,ymax);
    ppm("artifacts/gl-no-clear.ppm",bad,1280,800);ppm("artifacts/gl-cleared.ppm",good,1280,800);
    t.frame(true);assertion(good==t.pixels(),"GL clearing restores initial pixels at fractional target edge");
}
static void correctness(bool gpu,bool smart,int w=800,int h=600,float scale=1,int shadowMode=1) {
    Target target(gpu,smart,w,h); UI ui(target.c,1,true,shadowMode,scale); check(ui.root->scale(scale));
    uint64_t damage=0; printf("Initial %s %s %.4f ms\n",gpu?"gl":"sw",smart?"smart":"full",target.frame(true,&damage));
    auto initial=target.pixels(); std::string name=std::string("artifacts/")+(gpu?"gl":"sw")+(smart?"-smart":"-full")+(scale==1?"":"-dpi150")+(shadowMode==2?"-cached":""); ppm(name+".ppm",initial,w,h);
    auto at=[&](int x,int y){return initial[int(y*scale)*w+int(x*scale)];};
    assertion(pixelNear(at(10,10),19,25,37),"opaque background");
    assertion(pixelNear(at(670,420),70,210,130),"overlap follows z order");
    assertion(pixelNear(at(630,194),180,120,230),"rotation and translation produce expected interior");
    assertion(pixelNear(at(51,143),39,49,66),"rounded corner exposes board behind tile corner");
    assertion(pixelNear(at(470,330),40,73,139),"subtree opacity applied once at overlap");
    assertion(pixelNear(at(540,330),40,73,139),"single child agrees with opacity overlap");
    assertion(pixelNear(at(490,190),87,185,224),"nested clip retains inside");
    assertion(pixelNear(at(425,190),19,25,37)&&pixelNear(at(490,145),19,25,37),"both nested clips reject outside");
    assertion(!pixelNear(at(200,470),19,25,37,1),"drop shadow visible beyond board");
    target.frame(); assertion(initial==target.pixels(),"unchanged frame stable");
    ui.color(1,false); target.frame(false,&damage); auto hover=target.pixels();
    assertion(pixelNear(hover[int(155*scale)*w+int(75*scale)],70,95,130),"hover changes tile interior");
    assertion(hover!=initial,"hover produced changed pixels");
    printf("Hover dirty region summed area %llu / %d\n",(unsigned long long)damage,w*h);
    target.frame(true); assertion(hover==target.pixels(),"sparse hover equals forced full redraw");
    ui.geometry(1); target.frame(); auto geometry=target.pixels(); target.frame(true);
    assertion(geometry==target.pixels(),"geometry shrink restores old pixels exactly");
    ui.geometry(0); ui.color(0,false); target.frame(); assertion(initial==target.pixels(),"geometry and color reversal restores initial image");
    check(ui.moving->translate(110,-120));target.frame();auto transformed=target.pixels();target.frame(true);
    assertion(transformed==target.pixels(),"transform damage equals forced full redraw");
    assertion(pixelNear(transformed[int(194*scale)*w+int(630*scale)],19,25,37),"transform restores previous position");
    check(ui.moving->translate(48,-120));target.frame();
    if(scale==1) {
        // Rebind the same retained canvas and rerasterize external text at DPI.
        target.w=1200;target.h=900;target.data.assign(1200*900,0);target.target();ui.dpi(1.5f);target.frame(true);
        auto resized=target.pixels();ppm(name+"-resize150.ppm",resized,1200,900);
        assertion(pixelNear(resized[630*1200+1005],70,210,130),"resize and 150 percent DPI preserve logical geometry");
        target.w=w;target.h=h;target.data.assign(w*h,0);target.target();ui.dpi(1);target.frame(true);
        assertion(initial==target.pixels(),"same-canvas resize and DPI round trip restores pixels");
    }
    ppm(name+"-hover.ppm",hover,w,h);
}
static std::ofstream csv,raw;
static const char* shadowName(int mode) { return mode==0?"live-unbounded":mode==1?"live-bounded":"cached-bitmap"; }
static void record(const char* backend,const char* mode,int boards,int count,const char* workload,const std::vector<double>& a,uint64_t damage=0,int shadow=1) {
    auto s=a; std::sort(s.begin(),s.end()); double sum=0;for(double v:s)sum+=v;
    csv<<backend<<","<<mode<<","<<shadowName(shadow)<<",1280,800,"<<boards<<","<<count<<","<<workload<<",20,"<<s.size()<<","<<sum/s.size()<<","<<s[s.size()/2]<<","<<s[size_t(.95*(s.size()-1))]<<","<<s.back()<<","<<damage<<"\n";
    for(size_t i=0;i<a.size();i++)raw<<backend<<","<<mode<<","<<shadowName(shadow)<<","<<boards<<","<<workload<<","<<i<<","<<a[i]<<"\n";
    printf("%s %s %s boards=%d %s p50 %.4f p95 %.4f ms\n",backend,mode,shadowName(shadow),boards,workload,s[s.size()/2],s[size_t(.95*(s.size()-1))]); fflush(stdout);
}
static void benchmark(bool gpu,bool smart,int boards,int shadowMode) {
    Target t(gpu,smart,1280,800); UI ui(t.c,boards,false,shadowMode); check(ui.root->scale(1.333333f)); t.frame(true);
    for(const char* workload:{"unchanged","hover","all-colors","geometry","forced-full-hover"}) {
        std::vector<double> samples;
        for(int i=0;i<120;i++) {
            auto begin=Clock::now();
            if(std::string(workload)=="hover"||std::string(workload)=="forced-full-hover")ui.color(i,false);
            if(std::string(workload)=="all-colors")ui.color(i,true);
            if(std::string(workload)=="geometry")ui.geometry(i);
            t.frame(std::string(workload)=="forced-full-hover");
            if(i>=20)samples.push_back(elapsed(begin));
        }
        // Match the probe to the actual workload after putting it in state 0.
        ui.color(0,std::string(workload)=="all-colors");ui.geometry(0);t.frame();
        if(std::string(workload)=="geometry")ui.geometry(1);
        if(std::string(workload)=="hover"||std::string(workload)=="forced-full-hover"||std::string(workload)=="all-colors")ui.color(1,std::string(workload)=="all-colors");
        uint64_t damage=0;t.frame(std::string(workload)=="forced-full-hover",&damage);
        record(gpu?"gl":"sw",smart?"smart-request":"none",boards,ui.count,workload,samples,damage,shadowMode);
        auto sparse=t.pixels();t.frame(true);assertion(sparse==t.pixels(),"benchmark final state matches full redraw (outside timing)");
    }
    if(!gpu) {
        // Real full-frame texture upload into the same current desktop GL
        // context; glFinish makes the upload completion visible to CPU timing.
        GLuint texture;gGenTextures(1,&texture);gBindTexture(GL_TEXTURE_2D,texture);gTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,1280,800,0,GL_RGBA,GL_UNSIGNED_BYTE,t.data.data());gFinish();
        std::vector<double> samples;
        for(int i=0;i<120;i++){auto b=Clock::now();gTexSubImage2D(GL_TEXTURE_2D,0,0,0,1280,800,GL_RGBA,GL_UNSIGNED_BYTE,t.data.data());gFinish();if(i>=20)samples.push_back(elapsed(b));}
        record("sw-upload",smart?"smart-request":"none",boards,ui.count,"full-texture-upload-only",samples,0,shadowMode);
        samples.clear();
        for(int i=0;i<120;i++) { auto b=Clock::now();ui.color(i,false);t.frame();gBindTexture(GL_TEXTURE_2D,texture);gTexSubImage2D(GL_TEXTURE_2D,0,0,0,1280,800,GL_RGBA,GL_UNSIGNED_BYTE,t.data.data());gFinish();if(i>=20)samples.push_back(elapsed(b)); }
        record("sw-upload",smart?"smart-request":"none",boards,ui.count,"hover-plus-full-upload",samples,0,shadowMode);gDeleteTextures(1,&texture);
    }
}
int main(int argc,char** argv) {
    hr(CoInitializeEx(nullptr,COINIT_MULTITHREADED)); check(Initializer::init(0));
    if(!glfwInit()){fprintf(stderr,"GLFW init failed\n");return 5;}
    bool visible=argc>1&&std::string(argv[1])=="--view";
    bool checkOnly=argc>1&&std::string(argv[1])=="--check";
    glfwWindowHint(GLFW_VISIBLE,visible);glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR,3);glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR,3);glfwWindowHint(GLFW_OPENGL_PROFILE,GLFW_OPENGL_CORE_PROFILE);
    auto win=glfwCreateWindow(1280,900,"ThorVG isolated prototype",nullptr,nullptr);if(!win){fprintf(stderr,"GL 3.3 context unavailable\n");return 6;}glfwMakeContextCurrent(win);glfwSwapInterval(0);gFinish = reinterpret_cast<decltype(gFinish)>(glfwGetProcAddress("glFinish"));
gReadPixels = reinterpret_cast<decltype(gReadPixels)>(glfwGetProcAddress("glReadPixels"));
gGetString = reinterpret_cast<decltype(gGetString)>(glfwGetProcAddress("glGetString"));
gGenTextures = reinterpret_cast<decltype(gGenTextures)>(glfwGetProcAddress("glGenTextures"));
gBindTexture = reinterpret_cast<decltype(gBindTexture)>(glfwGetProcAddress("glBindTexture"));
gTexImage2D = reinterpret_cast<decltype(gTexImage2D)>(glfwGetProcAddress("glTexImage2D"));
gTexSubImage2D = reinterpret_cast<decltype(gTexSubImage2D)>(glfwGetProcAddress("glTexSubImage2D"));
gDeleteTextures = reinterpret_cast<decltype(gDeleteTextures)>(glfwGetProcAddress("glDeleteTextures"));

    printf("GL_VENDOR=%s\nGL_RENDERER=%s\nGL_VERSION=%s\n",gGetString(GL_VENDOR),gGetString(GL_RENDERER),gGetString(GL_VERSION));
    if(visible) {
        Target t(true,false,1280,900);UI ui(t.c,1,true,1,1.5f);check(ui.root->scale(1.5));
        glfwSetWindowTitle(win,"ThorVG native only | hover tiles | G toggles geometry | resize tests DPI resources");
        float zoom=1.5f;int oldHover=-1;bool oldG=false,small=false;
        while(!glfwWindowShouldClose(win)) {
            int width,height,ww,wh;glfwGetFramebufferSize(win,&width,&height);glfwGetWindowSize(win,&ww,&wh);
            if(width>0&&height>0) {
                if(t.w!=width||t.h!=height){t.w=width;t.h=height;t.data.resize(width*height);t.target();float next=std::min(width/800.f,height/600.f);if(next!=zoom){zoom=next;ui.dpi(zoom);}}
                double x,y;glfwGetCursorPos(win,&x,&y);x=x*width/ww/zoom;y=y*height/wh/zoom;
                int col=int((x-50)/104),row=int((y-142)/104),hover=-1;
                if(x>=50&&y>=142&&col>=0&&col<3&&row>=0&&row<3&&x<50+col*104+94&&y<142+row*104+94)hover=row*3+col;
                if(hover!=oldHover){if(oldHover>=0)check(ui.tiles[oldHover]->fill(48,61,80));if(hover>=0)check(ui.tiles[hover]->fill(70,95,130));oldHover=hover;}
                bool g=glfwGetKey(win,GLFW_KEY_G)==GLFW_PRESS;if(g&&!oldG){small=!small;ui.geometry(small);}oldG=g;
                t.frame(true);glfwSwapBuffers(win);
            }
            glfwWaitEvents();
        }
    }
    else {
        glClearDiagnostic();
        for(bool gpu:{false,true})for(bool smart:{false,true})correctness(gpu,smart);
        correctness(false,true,1200,900,1.5f);correctness(true,false,1200,900,1.5f);
        correctness(false,true,800,600,1,2);correctness(true,false,800,600,1,2);
        if(!checkOnly) {
        csv.open("artifacts/timings.csv");csv<<"backend,mode,shadow,width,height,boards,paint_objects,workload,warmup,samples,mean_ms,p50_ms,p95_ms,max_ms,probe_dirty_area\n";
        raw.open("artifacts/samples.csv");raw<<"backend,mode,shadow,boards,workload,sample,ms\n";
        for(int shadow:{0,1,2})for(bool gpu:{false,true})for(bool smart:{false,true})for(int boards:{1,64})benchmark(gpu,smart,boards,shadow);
        }
    }
    glfwDestroyWindow(win);glfwTerminate();check(Initializer::term());CoUninitialize();printf("ASSERTION_FAILURES=%d\n",failures);return failures?1:0;
}
