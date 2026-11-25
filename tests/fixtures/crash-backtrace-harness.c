#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: backtrace line %d\n", __LINE__); _Exit(86); } } while (0)
typedef uintptr_t vm_address_t;
static uintptr_t frames[256] __attribute__((aligned(16)));
static size_t stackSize = sizeof(frames);
static unsigned decoded, printed;
static void *fixture_stack_address(pthread_t thread) { (void)thread; return frames + 256; }
static size_t fixture_stack_size(pthread_t thread) { (void)thread; return stackSize; }
static uintptr_t fixture_decode(uintptr_t frame, uintptr_t *address) {
    assert(frame >= (uintptr_t)frames && frame <= (uintptr_t)(frames + 254));
    assert((frame - (uintptr_t)frames) % (2 * sizeof(uintptr_t)) == 0);
    decoded++;
    uintptr_t *words = (uintptr_t *)frame;
    if (address) *address = words[1];
    return words[0];
}
#define pthread_get_stackaddr_np fixture_stack_address
#define pthread_get_stacksize_np fixture_stack_size
#define pthread_stack_frame_decode_np fixture_decode
/* PRODUCTION_WALKER */
static void crashreporter_dump_backtrace_line(FILE *stream, vm_address_t address) {
    (void)stream;
    assert(printed < 100 && address == 1000 + printed);
    printed++;
}
/* PRODUCTION_DUMP */
static void prepare(unsigned length) {
    memset(frames, 0, sizeof(frames));
    for (unsigned i = 0; i < length; i++) {
        frames[2*i] = i + 1 < length ? (uintptr_t)&frames[2*(i+1)] : 0;
        frames[2*i+1] = 1000 + i;
    }
    decoded = printed = 0;
}
int main(void) {
    vm_address_t output[100]; unsigned count;
    prepare(100);
    crashreporter_dump_backtrace(NULL, pthread_self(), frames);
    assert(printed == 100 && decoded == 100);
    prepare(3);
    crashreporter_dump_backtrace(NULL, pthread_self(), frames);
    assert(printed == 3 && decoded == 3);
    prepare(6);
    pthread_backtrace(pthread_self(), output, 2, &count, 2, frames);
    assert(count == 2 && output[0] == 1002 && output[1] == 1003);
    prepare(1); frames[0] = (uintptr_t)frames;
    pthread_backtrace(pthread_self(), output, 100, &count, 0, frames);
    assert(count == 1 && decoded == 1);
    uintptr_t invalid[] = {0, (uintptr_t)frames - 8, (uintptr_t)(frames + 256),
        (uintptr_t)(frames + 255), (uintptr_t)frames + 1};
    for (unsigned i = 0; i < sizeof(invalid)/sizeof(invalid[0]); i++) {
        decoded = 0;
        pthread_backtrace(pthread_self(), output, 100, &count, 0, (void *)invalid[i]);
        assert(!count && !decoded);
    }
    decoded = 0; stackSize = 1;
    pthread_backtrace(pthread_self(), output, 100, &count, 0, frames);
    assert(!count && !decoded);
    stackSize = sizeof(frames);
    pthread_backtrace(pthread_self(), output, 0, &count, 0, frames);
    assert(!count && !decoded);
    puts("PASS production backtrace: full buffer, skip/limit, cyclic and invalid frame boundaries");
}
