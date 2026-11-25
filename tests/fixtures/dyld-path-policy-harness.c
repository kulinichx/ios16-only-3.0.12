#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: dyld policy line %d\n", __LINE__); _Exit(86); } } while (0)
/* PRODUCTION_POLICY */
int main(void) {
    const char *web[] = {"/usr/libexec/xpcproxy", "com.apple.WebKit.WebContent.test", NULL};
    const char *empty[] = {NULL};
    assert(!process_force_dyld_patch(NULL, NULL));
    assert(!process_force_dyld_patch(NULL, web));
    assert(!process_force_dyld_patch(NULL, empty));
    assert(!process_force_dyld_patch("/usr/libexec/xpcproxy", NULL));
    assert(!process_force_dyld_patch("/usr/libexec/xpcproxy", empty));
    assert(process_force_dyld_patch("/usr/libexec/xpcproxy", web));
    assert(process_force_dyld_patch("/System/Library/Foo/com.apple.WebKit.WebContent", NULL));
    assert(process_force_dyld_patch("/private/preboot/Cryptexes/OS/com.apple.WebKit.WebContent.CaptivePortal", NULL));
    assert(!process_force_dyld_patch("/tmp/com.apple.WebKit.WebContent", web));
    assert(!process_force_dyld_patch("/System/Library/Foo/Other", web));
    puts("PASS production dyld policy: missing path, incomplete argv and preserved WebContent routing");
}
