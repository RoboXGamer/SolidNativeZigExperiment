// Optional exact VM allocator accounting. Compiled out of ordinary builds.
#ifndef UI_PROBES
#define UI_PROBES 0
#endif
typedef struct { uint64_t allocations, frees, live_count, live_bytes, high_count, high_bytes, roots; } UiMemory;
static UiMemory memory;
static uint64_t fail_after = UINT64_MAX;
#if UI_PROBES
typedef union { max_align_t alignment; size_t bytes; } Allocation;
static void *tracked_malloc(void *opaque, size_t bytes) {
    (void)opaque;
    if (bytes > SIZE_MAX-sizeof(Allocation) || memory.allocations >= fail_after) return NULL;
    Allocation *h=malloc(sizeof(*h)+bytes); if(!h)return NULL; h->bytes=bytes;
    memory.allocations++; memory.live_count++; memory.live_bytes+=bytes;
    if(memory.live_count>memory.high_count)memory.high_count=memory.live_count;
    if(memory.live_bytes>memory.high_bytes)memory.high_bytes=memory.live_bytes;
    return h+1;
}
static void tracked_free(void *opaque,void *p) {
    (void)opaque;if(!p)return;Allocation *h=(Allocation*)p-1;
    memory.frees++;memory.live_count--;memory.live_bytes-=h->bytes;free(h);
}
static void *tracked_calloc(void *opaque,size_t count,size_t bytes) {
    if(bytes && count>SIZE_MAX/bytes)return NULL;
    void *p=tracked_malloc(opaque,count*bytes);if(p)memset(p,0,count*bytes);return p;
}
static void *tracked_realloc(void *opaque,void *p,size_t bytes) {
    if(!bytes){tracked_free(opaque,p);return NULL;}
    if(!p)return tracked_malloc(opaque,bytes);
    Allocation *h=(Allocation*)p-1;
    void *next=tracked_malloc(opaque,bytes);if(!next)return NULL;
    memcpy(next,p,bytes<h->bytes?bytes:h->bytes);tracked_free(opaque,p);return next;
}
static size_t tracked_size(const void *p){return p?((const Allocation*)p-1)->bytes:0;}
static const JSMallocFunctions tracked_functions={tracked_calloc,tracked_malloc,tracked_free,tracked_realloc,tracked_size};
#endif
void ui_memory(UiMemory *out){*out=memory;}
void ui_fail_allocations(int enabled){fail_after=enabled?memory.allocations:UINT64_MAX;}
int ui_probes_enabled(void){return UI_PROBES;}
static char log_lines[UI_PROBES ? 32 : 1][UI_PROBES ? 1024 : 1];
static unsigned log_count, log_dropped;
unsigned ui_log_count(void){return log_count;}
unsigned ui_log_dropped(void){return log_dropped;}
const char *ui_log_line(unsigned index){return index<log_count?log_lines[index]:"";}
static void record_log(const char *text){
#if UI_PROBES
    if(log_count==32){memmove(log_lines,log_lines+1,31*sizeof(log_lines[0]));log_count--;log_dropped++;}
    snprintf(log_lines[log_count++],sizeof(log_lines[0]),"%s",text);
#else
    (void)text;
#endif
}
