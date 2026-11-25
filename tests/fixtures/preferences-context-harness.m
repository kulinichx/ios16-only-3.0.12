#import <Foundation/Foundation.h>
#include <assert.h>
#include <pthread.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: preferences line %d\n", __LINE__); _Exit(86); } } while (0)

#undef NSLog
#define NSLog(...) ((void)0)
typedef id xpc_object_t;
typedef id xpc_connection_t;
typedef struct { pid_t pid; uid_t uid; } audit_token_t;
static void xpc_connection_get_audit_token(id connection, audit_token_t *token) {
    token->pid = [connection intValue]; token->uid = 501;
}
static pid_t audit_token_to_pid(audit_token_t token) { return token.pid; }
static uid_t audit_token_to_euid(audit_token_t token) { return token.uid; }
static pid_t __thread gCurrentClientPid;
static void *new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id, xpc_object_t, xpc_connection_t, void *);
static void *DISPATCH_orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id self, xpc_object_t message, xpc_connection_t connection, void *reply) {
    (void)self; (void)reply;
    assert(gCurrentClientPid == [connection intValue]);
    switch ([message intValue]) {
        case 1:
            assert(new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(nil, @0, @202, NULL) == (void *)0x1234);
            assert(gCurrentClientPid == [connection intValue]);
            break;
        case 2:
            @throw [NSException exceptionWithName:@"Fixture" reason:nil userInfo:nil];
        case 3:
            for (unsigned i = 0; i < 100; i++) { usleep(100); assert(gCurrentClientPid == [connection intValue]); }
            break;
    }
    return (void *)0x1234;
}
/* PRODUCTION_CONTEXT */
static bool is_apple_internal_identifier(const char *identifier) { return !strcmp(identifier, "com.apple.Terminal"); }
/* PRODUCTION_PATH_POLICY */
static void *thread_request(void *input) {
    @autoreleasepool {
        pid_t pid = (pid_t)(uintptr_t)input;
        assert(gCurrentClientPid == 0);
        new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(nil, @3, @(pid), NULL);
        assert(gCurrentClientPid == 0);
    }
    return NULL;
}
int main(void) {
    @autoreleasepool {
        gCurrentClientPid = 17;
        assert(new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(nil, @1, @101, NULL) == (void *)0x1234);
        assert(gCurrentClientPid == 17);
        BOOL caught = NO;
        @try { new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(nil, @2, @303, NULL); }
        @catch (NSException *exception) { caught = [exception.name isEqual:@"Fixture"]; }
        assert(caught && gCurrentClientPid == 17);
        gCurrentClientPid = 0;
        new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(nil, @0, @404, NULL);
        assert(gCurrentClientPid == 0);
        pthread_t threads[2];
        assert(!pthread_create(&threads[0], NULL, thread_request, (void *)501));
        assert(!pthread_create(&threads[1], NULL, thread_request, (void *)502));
        assert(!pthread_join(threads[0], NULL) && !pthread_join(threads[1], NULL));
        assert(!preferencePlistNeedsRedirection(nil));
        assert(!preferencePlistNeedsRedirection((id)@42));
        assert(!preferencePlistNeedsRedirection(@""));
        assert(!preferencePlistNeedsRedirection(@"/var/mobile/Library/Preferences/com.apple.springboard.plist"));
        assert(!preferencePlistNeedsRedirection(@"/var/mobile/Library/Preferences/.GlobalPreferences.plist"));
        assert(preferencePlistNeedsRedirection(@"/var/mobile/Library/Preferences/com.apple.Terminal.plist"));
        assert(preferencePlistNeedsRedirection(@"/private/var/mobile/Library/Preferences/org.example.tweak.plist"));
        assert(!preferencePlistNeedsRedirection(@"/tmp/org.example.tweak.plist"));
    }
    puts("PASS production preferences: nested/throwing/threaded caller scopes and path policy");
}
