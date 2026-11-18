// Only built with -Ddriver=true. This worker frames bytes; only the UI thread
// parses/executes requests. A single owned request provides backpressure without
// retaining tree, arena, or QuickJS pointers on the worker.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <bcrypt.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
extern void glfwPostEmptyEvent(void);
#define FRAME 65536
static HANDLE worker, stopped, replied, sent_event, pipe_handle;
static CRITICAL_SECTION lock;
static char request[FRAME+1], response[FRAME+1], pipe_name[256];
static size_t request_len, response_len;
static int pending;
static uint64_t connection;
static PSECURITY_DESCRIPTOR security;
static int exchange(const char *data, size_t len) {
    EnterCriticalSection(&lock);
    if(len!=SIZE_MAX){memcpy(request, data, len); request[len]=0;} request_len=len; pending=1;
    LeaveCriticalSection(&lock);
    glfwPostEmptyEvent();
    HANDLE events[]={stopped,replied};
    return WaitForMultipleObjects(2,events,FALSE,INFINITE)==WAIT_OBJECT_0+1;
}
static DWORD WINAPI serve(void *unused) {
    (void)unused;
    while (WaitForSingleObject(stopped,0)==WAIT_TIMEOUT) {
        if (!ConnectNamedPipe(pipe_handle,NULL) && GetLastError()!=ERROR_PIPE_CONNECTED) break;
        EnterCriticalSection(&lock);
        if(connection>=9007199254740991ULL){LeaveCriticalSection(&lock);DisconnectNamedPipe(pipe_handle);break;}
        connection++; LeaveCriticalSection(&lock);
        char frame[FRAME+1]; size_t used=0; int connected=1;
        while (connected && WaitForSingleObject(stopped,0)==WAIT_TIMEOUT) {
            // Read in bounded chunks, preserving fragments and multiple frames.
            char chunk[4096]; DWORD read=0;
            if (!ReadFile(pipe_handle,chunk,sizeof(chunk),&read,NULL) || !read) break;
            for (DWORD i=0;i<read;i++) {
                if (chunk[i]=='\n') {
                    if (!exchange(frame,used)) { connected=0; break; }
                    size_t sent=0;
                    while(sent<response_len) { DWORD wrote=0; if(!WriteFile(pipe_handle,response+sent,(DWORD)(response_len-sent),&wrote,NULL)||!wrote) {connected=0;break;} sent+=wrote; }
                    // A successful WriteFile only fills the pipe buffer. Join
                    // client consumption before acknowledging close, otherwise
                    // DisconnectNamedPipe can discard the final receipt.
                    if(connected && !FlushFileBuffers(pipe_handle))connected=0;
                    SetEvent(sent_event);
                    used=0;
                } else if (used==FRAME) { connected=0; break; }
                else frame[used++]=chunk[i];
            }
        }
        if (WaitForSingleObject(stopped,0)==WAIT_TIMEOUT) exchange(NULL,SIZE_MAX); // cleanup held input, even after EOF
        DisconnectNamedPipe(pipe_handle);
    }
    return 0;
}
int ui_driver_start(void) {
    const char *name=getenv("SOLID_NATIVE_PIPE"), *token=getenv("SOLID_NATIVE_TOKEN");
    if(!name || !token || strlen(token)<16 || strlen(name)>180) return 0;
    if(BCryptGenRandom(NULL,(PUCHAR)&connection,sizeof(connection),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)return 0;
    connection &= 9007199254740991ULL;
    // Restrict the pipe DACL to the current user's SID; reject remote clients.
    HANDLE access; DWORD bytes=0;
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&access)) return 0;
    GetTokenInformation(access,TokenUser,NULL,0,&bytes);
    TOKEN_USER *user=malloc(bytes); char *sid=NULL; char acl[512];
    int ok=user && GetTokenInformation(access,TokenUser,user,bytes,&bytes) && ConvertSidToStringSidA(user->User.Sid,&sid);
    CloseHandle(access); free(user); if(!ok) return 0;
    snprintf(acl,sizeof(acl),"D:P(A;;GA;;;%s)",sid); LocalFree(sid);
    if(!ConvertStringSecurityDescriptorToSecurityDescriptorA(acl,SDDL_REVISION_1,&security,NULL))return 0;
    SECURITY_ATTRIBUTES sa={sizeof(sa),security,FALSE};
    snprintf(pipe_name,sizeof(pipe_name),"\\\\.\\pipe\\%s",name);
    pipe_handle=CreateNamedPipeA(pipe_name,PIPE_ACCESS_DUPLEX|FILE_FLAG_FIRST_PIPE_INSTANCE,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,FRAME,FRAME,0,&sa);
    if(pipe_handle==INVALID_HANDLE_VALUE){LocalFree(security);security=NULL;return 0;}
    InitializeCriticalSection(&lock); stopped=CreateEventW(NULL,TRUE,FALSE,NULL); replied=CreateEventW(NULL,FALSE,FALSE,NULL);sent_event=CreateEventW(NULL,TRUE,TRUE,NULL);
    if(stopped && replied && sent_event) worker=CreateThread(NULL,0,serve,NULL,0,NULL);
    if(worker)return 1;
    if(stopped)CloseHandle(stopped);if(replied)CloseHandle(replied);if(sent_event)CloseHandle(sent_event);
    CloseHandle(pipe_handle);DeleteCriticalSection(&lock);LocalFree(security);security=NULL;return 0;
}
int ui_driver_poll(const char **data, size_t *len, uint64_t *session) {
    EnterCriticalSection(&lock); int ready=pending;
    if(ready){*data=request;*len=request_len;*session=connection;pending=0;}
    LeaveCriticalSection(&lock); return ready;
}
void ui_driver_reply(const char *data,size_t len) {
    if(len>=FRAME)len=0;
    memcpy(response,data,len); response[len]='\n'; response_len=len+1; ResetEvent(sent_event);SetEvent(replied);
}
void ui_driver_flush(void){WaitForSingleObject(sent_event,2000);}
void ui_driver_stop(void) {
    if(!worker)return;
    SetEvent(stopped); CancelSynchronousIo(worker); CancelIoEx(pipe_handle,NULL); DisconnectNamedPipe(pipe_handle);
    WaitForSingleObject(worker,INFINITE); CloseHandle(worker); CloseHandle(pipe_handle); CloseHandle(stopped); CloseHandle(replied);CloseHandle(sent_event);
    DeleteCriticalSection(&lock); LocalFree(security); worker=NULL;
}
