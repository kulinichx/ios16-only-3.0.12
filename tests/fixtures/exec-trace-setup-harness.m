#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: trace setup line %d\n", __LINE__); _Exit(86); } } while (0)
#ifndef ARM_THREAD_STATE64
#define ARM_THREAD_STATE64 6
#endif
#ifndef PT_ATTACHEXC
#define PT_ATTACHEXC 14
#endif
#define JBLogError(...) ((void)0)
#define JBLogDebug(...) ((void)0)
static NSLock *trace_data_lock;
static NSMutableDictionary *trace_data_record;
static bool canTrace = true;
static int taskError, allocationFailure, getError, setError, attachError;
static int heldTask, heldSaved, allocations, attachCalls, restoreCalls, kills;
static int portError, insertError, threadError, heldExceptionPort, serverAttempts, threadCalls, detachCalls;
/* PRODUCTION_TRACE_TYPE */
static void *fixture_calloc(size_t count, size_t size) {
    if(allocationFailure) return NULL;
    void *result=calloc(count,size); assert(result); allocations++; return result;
}
static void fixture_free(void *value) { assert(value && allocations>0); allocations--; free(value); }
static bool proc_cantrace(pid_t pid) { assert(pid==123); return canTrace; }
static kern_return_t fixture_task_for_pid(mach_port_t self, int pid, mach_port_t *task) {
    (void)self; assert(pid==123);
    if(taskError) return taskError;
    heldTask++; *task=77; return KERN_SUCCESS;
}
static kern_return_t fixture_deallocate(mach_port_t self, mach_port_t port) {
    (void)self;
    if(port==77) { assert(heldTask==1); heldTask--; }
    else { assert((port==90 || port==91) && heldSaved>0); heldSaved--; }
    return KERN_SUCCESS;
}
static kern_return_t fixture_get_ports(mach_port_t task, exception_mask_t mask, exception_mask_t *masks,
    mach_msg_type_number_t *count, mach_port_t *ports, exception_behavior_t *behaviors, thread_state_flavor_t *flavors) {
    assert(task==77 && mask==EXC_MASK_SOFTWARE);
    if(getError) return getError;
    if(*count<2) { *count=2; return MIG_ARRAY_TOO_LARGE; }
    *count=2;
    for(unsigned i=0;i<2;i++) { masks[i]=1u<<i; ports[i]=90+i; behaviors[i]=EXCEPTION_DEFAULT; flavors[i]=ARM_THREAD_STATE64; }
    heldSaved+=2; return KERN_SUCCESS;
}
static kern_return_t fixture_set_ports(mach_port_t task, exception_mask_t mask, mach_port_t port,
    exception_behavior_t behavior, thread_state_flavor_t flavor) {
    (void)mask; (void)behavior; (void)flavor; assert(task==77);
    if(port==55) return setError;
    assert(port==90 || port==91); restoreCalls++; return KERN_SUCCESS;
}
static kern_return_t fixture_allocate(mach_port_t self, mach_port_right_t right, mach_port_t *port) {
    (void)self; assert(right==MACH_PORT_RIGHT_RECEIVE); serverAttempts++;
    if(portError) return portError;
    assert(!heldExceptionPort); heldExceptionPort++; *port=55; return KERN_SUCCESS;
}
static kern_return_t fixture_insert(mach_port_t self, mach_port_t name, mach_port_t port, mach_msg_type_name_t type) {
    (void)self; (void)type; assert(name==55 && port==55 && heldExceptionPort); return insertError;
}
static kern_return_t fixture_destroy(mach_port_t self, mach_port_t port) {
    (void)self; assert(port==55 && heldExceptionPort==1); heldExceptionPort--; return KERN_SUCCESS;
}
static int fixture_create(pthread_t *thread, const pthread_attr_t *attr, void *(*entry)(void *), void *input) {
    (void)attr; (void)entry; assert((uintptr_t)input==55 && heldExceptionPort); threadCalls++;
    if(threadError) return threadError;
    *thread=pthread_self(); return 0;
}
static int fixture_detach(pthread_t thread) { assert(pthread_equal(thread,pthread_self())); detachCalls++; return 0; }
static int fixture_ptrace(int operation, pid_t pid, void *address, int signal) {
    (void)address; (void)signal; assert(operation==PT_ATTACHEXC && pid==123); attachCalls++; return attachError;
}
static int fixture_kill(pid_t pid, int signal) { assert(pid==123 && signal==SIGKILL); kills++; return 0; }
static void *exception_server(void *input) { return input; }
static void finish_process_trace(trace_data_t *data, bool success) {
    assert(success);
    for(unsigned i=0;i<data->saved_exception_types_count;i++) fixture_deallocate(0,data->saved_ports[i]);
    [trace_data_record removeObjectForKey:@(data->pid)]; fixture_free(data);
}
#define calloc fixture_calloc
#define free fixture_free
#define task_for_pid fixture_task_for_pid
#define mach_port_deallocate fixture_deallocate
#define task_get_exception_ports fixture_get_ports
#define task_set_exception_ports fixture_set_ports
#define mach_port_allocate fixture_allocate
#define mach_port_insert_right fixture_insert
#define mach_port_destroy fixture_destroy
#define pthread_create fixture_create
#define pthread_detach fixture_detach
#define ptrace fixture_ptrace
#define kill fixture_kill
/* PRODUCTION_TRACE_SETUP */
static void reset(void) {
    assert(!heldTask && !heldSaved && !allocations && !trace_data_record.count);
    canTrace=true; taskError=allocationFailure=getError=setError=attachError=0;
    attachCalls=restoreCalls=kills=0;
}
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if(argc>1) {
            if(!strcmp(argv[1],"allocate")) portError=KERN_RESOURCE_SHORTAGE;
            else if(!strcmp(argv[1],"insert")) insertError=KERN_FAILURE;
            else { assert(!strcmp(argv[1],"thread")); threadError=EAGAIN; }
            assert(execTraceProcess(123,0x1000)==-1);
            assert(execTraceProcess(123,0x1000)==-1);
            assert(serverAttempts==1 && !heldExceptionPort && !heldTask && !allocations && !attachCalls && !detachCalls);
            assert(threadCalls==(threadError?1:0));
            puts("PASS production exec tracing rejects failed server initialization");
            return 0;
        }
        reset(); assert(execTraceProcess(123,0x1000)==0);
        assert(serverAttempts==1 && threadCalls==1 && detachCalls==1 && heldExceptionPort==1);
        trace_data_t *record=[trace_data_record[@123] pointerValue];
        assert(record && record->saved_exception_types_count==2 && heldSaved==2 && !heldTask);
        finish_process_trace(record,true);
        reset(); canTrace=false;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !allocations);
        reset(); taskError=KERN_FAILURE;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !allocations);
        reset(); allocationFailure=1;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !allocations);
        reset(); getError=KERN_FAILURE;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !heldSaved && !allocations && !attachCalls);
        reset(); setError=KERN_FAILURE;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !heldSaved && !allocations && !attachCalls);
        reset(); attachError=-1;
        assert(execTraceProcess(123,0x1000)==-1 && !heldTask && !heldSaved && !allocations && !trace_data_record.count);
        assert(restoreCalls==2 && kills==1);
        reset();
    }
    puts("PASS production exec trace setup: array capacity, allocation/get/set/attach failures and right ownership");
}
