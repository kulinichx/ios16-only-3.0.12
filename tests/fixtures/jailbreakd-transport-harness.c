#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: transport line %d\n", __LINE__); _Exit(86); } } while (0)
typedef unsigned mach_port_t;
typedef struct fixture_object { int references; } *xpc_object_t;
static struct fixture_object pipeObject, replyObject, requestObject;
static bool portFailure, pipeFailure;
static int routineError, routineCalls, portsHeld, pipeReleases, replyReleases;
#define MACH_PORT_VALID(port) ((port) != 0)
#define JBLogError(...) ((void)0)
static mach_port_t jailbreakdClientPort(void) {
    if(portFailure) return 0;
    portsHeld++; return 77;
}
static xpc_object_t xpc_pipe_create_from_port(mach_port_t port, uint32_t flags) {
    (void)flags; assert(port==77);
    if(pipeFailure) return NULL;
    pipeObject.references++; return (xpc_object_t)&pipeObject;
}
static int xpc_pipe_routine(xpc_object_t pipe, xpc_object_t request, xpc_object_t *reply) {
    assert(pipe==(xpc_object_t)&pipeObject && request==(xpc_object_t)&requestObject);
    routineCalls++;
    replyObject.references++; *reply=(xpc_object_t)&replyObject;
    return routineError;
}
static int mach_task_self(void) { return 1; }
static void mach_port_deallocate(int task, mach_port_t port) {
    assert(task==1 && port==77 && portsHeld==1); portsHeld--;
}
static void xpc_release(xpc_object_t object) {
    assert(object && object->references>0);
    object->references--;
    if(object==(xpc_object_t)&pipeObject) pipeReleases++;
    else { assert(object==(xpc_object_t)&replyObject); replyReleases++; }
}
/* PRODUCTION_TRANSPORT */
static void reset(void) {
    assert(!portsHeld && !pipeObject.references && !replyObject.references);
    portFailure=pipeFailure=false; routineError=routineCalls=pipeReleases=replyReleases=0;
}
int main(void) {
    reset(); portFailure=true;
    assert(!jailbreakdXpcRequest((xpc_object_t)&requestObject) && !portsHeld && !routineCalls);
    reset(); pipeFailure=true;
    assert(!jailbreakdXpcRequest((xpc_object_t)&requestObject) && !portsHeld && !routineCalls && !pipeReleases);
    reset(); routineError=5;
    assert(!jailbreakdXpcRequest((xpc_object_t)&requestObject) && !portsHeld && pipeReleases==1 && replyReleases==1);
    reset();
    xpc_object_t reply=jailbreakdXpcRequest((xpc_object_t)&requestObject);
    assert(reply==(xpc_object_t)&replyObject && !portsHeld && pipeReleases==1 && !replyReleases);
    xpc_release(reply);
    reset();
    puts("PASS production jailbreakd transport: invalid port, pipe failure, failed/successful reply ownership");
}
