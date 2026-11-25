// Exercise the production dispatcher with fault-injected XPC and real descriptor layouts.
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { unsigned value; } audit_token_t;
typedef unsigned mach_port_t;
typedef struct { int unused; } *xpc_object_t;
#define XPC_TYPE_DICTIONARY 1
#define JBSERVER_MAX_ARGS 8
/* PRODUCTION_TYPES */

static struct { int unused; } requestStorage, replyStorage;
static unsigned calls, replies, released, closed;
static bool hasReply = true;
static uint64_t domainNumber = 1, actionNumber = 1, outputNumber;
static uint8_t payload[] = {1, 2, 3};
static uint8_t outputBytes[8];
static size_t outputLength;
static int xpc_get_type(xpc_object_t object) { (void)object; return XPC_TYPE_DICTIONARY; }
static bool roothide_handle_xpc_msg(xpc_object_t object) { (void)object; return false; }
static xpc_object_t xpc_dictionary_get_value(xpc_object_t object, const char *name) { (void)name; return object; }
static uint64_t xpc_dictionary_get_uint64(xpc_object_t object, const char *name)
{ (void)object; return !strcmp(name,"jb-domain") ? domainNumber : !strcmp(name,"action") ? actionNumber : 42; }
static void xpc_dictionary_get_audit_token(xpc_object_t object, audit_token_t *token) { (void)object; token->value = 7; }
static bool xpc_dictionary_get_bool(xpc_object_t object, const char *name) { (void)object; (void)name; return true; }
static int xpc_dictionary_dup_fd(xpc_object_t object, const char *name) { (void)object; (void)name; return 19; }
static mach_port_t xpc_dictionary_extract_mach_recv(xpc_object_t object, const char *name) { (void)object; (void)name; return 20; }
static mach_port_t xpc_dictionary_copy_mach_send(xpc_object_t object, const char *name) { (void)object; (void)name; return 21; }
static const char *xpc_dictionary_get_string(xpc_object_t object, const char *name) { (void)object; (void)name; return "test"; }
static const void *xpc_dictionary_get_data(xpc_object_t object, const char *name, size_t *length)
{ (void)object; (void)name; *length = sizeof(payload); return payload; }
static xpc_object_t xpc_dictionary_get_array(xpc_object_t object, const char *name) { (void)name; return object; }
static xpc_object_t xpc_dictionary_get_dictionary(xpc_object_t object, const char *name) { (void)name; return object; }
static xpc_object_t xpc_dictionary_create_reply(xpc_object_t object)
{ (void)object; return hasReply ? (xpc_object_t)&replyStorage : NULL; }
static void xpc_dictionary_set_bool(xpc_object_t object, const char *name, bool value) { (void)object; (void)name; outputNumber = value; }
static void xpc_dictionary_set_uint64(xpc_object_t object, const char *name, uint64_t value) { (void)object; (void)name; outputNumber = value; }
static void xpc_dictionary_set_fd(xpc_object_t object, const char *name, int value) { (void)object; (void)name; outputNumber = value; }
static void xpc_dictionary_set_mach_recv(xpc_object_t object, const char *name, mach_port_t value) { (void)object; (void)name; outputNumber = value; }
static void xpc_dictionary_set_mach_send(xpc_object_t object, const char *name, mach_port_t value) { (void)object; (void)name; outputNumber = value; }
static void xpc_dictionary_set_string(xpc_object_t object, const char *name, const char *value) { (void)object; (void)name; (void)value; }
static void xpc_dictionary_set_data(xpc_object_t object, const char *name, const void *bytes, size_t length)
{ (void)object; (void)name; assert(length <= sizeof(outputBytes)); memcpy(outputBytes,bytes,length); outputLength = length; }
static void xpc_dictionary_set_value(xpc_object_t object, const char *name, xpc_object_t value) { (void)object; (void)name; (void)value; }
static void xpc_dictionary_set_int64(xpc_object_t object, const char *name, int64_t value) { (void)object; assert(!strcmp(name,"result") && value == 0); }
static void xpc_pipe_routine_reply(xpc_object_t object) { assert(object); replies++; }
static void xpc_release(xpc_object_t object) { assert(object); released++; }
static int mock_close(int fd) { assert(fd == 19); closed++; return 0; }
#define close mock_close
/* PRODUCTION_DISPATCH */
#undef close

static unsigned mode;
static int handler(void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *h)
{
    (void)e; (void)f; (void)g; (void)h; calls++;
    assert(a == payload && (uintptr_t)b == sizeof(payload));
    if (mode == 0) {
        assert((uintptr_t)c == 1 && d);
        *(void **)d = (void *)(uintptr_t)99;
    } else if (mode == 1) {
        assert(c && d && (uintptr_t)e == 1);
        void *bytes = malloc(sizeof(payload)); assert(bytes); memcpy(bytes,payload,sizeof(payload));
        *(void **)c = bytes; *(void **)d = (void *)(uintptr_t)sizeof(payload);
    } else {
        assert((intptr_t)c == 19);
    }
    return 0;
}
int main(void)
{
    /* PRODUCTION_ARGUMENT_ARRAYS */
    // Allocate the flexible action array using the production public structs.
    struct jbserver_domain *domain = calloc(1,sizeof(*domain) + 2 * sizeof(struct jbserver_action));
    assert(domain);
    struct jbserver_domain *domains[] = {domain,NULL};
    struct jbserver_impl server = {.maxDomain = 1, .domains = domains};
    jbserver_arg descriptors[9] = {
        {.name="data",.type=JBS_TYPE_DATA}, {.name="attach",.type=JBS_TYPE_BOOL},
        {.name="output",.type=JBS_TYPE_UINT64,.out=true}, {0}
    };
    domain->actions[0] = (struct jbserver_action){.handler=handler,.args=descriptors};
    xpc_object_t request = (xpc_object_t)&requestStorage;
    assert(jbserver_received_xpc_message(&server,request) == 0);
    assert(calls == 1 && outputNumber == 99 && replies == 1 && released == 1);
    mode = 1;
    descriptors[1] = (jbserver_arg){.name="out-data",.type=JBS_TYPE_DATA,.out=true};
    descriptors[2] = (jbserver_arg){.name="tail",.type=JBS_TYPE_BOOL};
    assert(jbserver_received_xpc_message(&server,request) == 0);
    assert(calls == 2 && outputLength == sizeof(payload) && !memcmp(outputBytes,payload,sizeof(payload)));
    mode = 2;
    descriptors[1] = (jbserver_arg){.name="fd",.type=JBS_TYPE_FD};
    descriptors[2] = (jbserver_arg){0};
    assert(jbserver_received_xpc_message(&server,request) == 0 && closed == 1 && calls == 3);
    hasReply = false;
    assert(jbserver_received_xpc_message(&server,request) == -1 && calls == 3 && closed == 1);
    hasReply = true;
    for (unsigned i=0;i<7;i++) descriptors[i] = (jbserver_arg){.name="single",.type=JBS_TYPE_UINT64};
    descriptors[7] = (jbserver_arg){.name="overflow",.type=JBS_TYPE_DATA};
    assert(jbserver_received_xpc_message(&server,request) == -1 && calls == 3);
    descriptors[0] = (jbserver_arg){.name="bad",.type=(jbserver_type)100};
    assert(jbserver_received_xpc_message(&server,request) == -1 && calls == 3);
    descriptors[0] = (jbserver_arg){.name="bad",.type=JBS_TYPE_CALLER_TOKEN,.out=true};
    assert(jbserver_received_xpc_message(&server,request) == -1 && calls == 3);
    free(domain);
    puts("PASS production XPC DATA input/output slot mapping, following fields, FD cleanup and reply/layout rejection");
    return 0;
}
