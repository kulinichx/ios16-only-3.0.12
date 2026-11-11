#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <errno.h>

enum { CTL_KERN = 1, KERN_ARGMAX, KERN_PROC, KERN_PROC_ALL, KERN_PROCARGS2 };
struct kinfo_proc { struct { pid_t p_pid; } kp_proc; };
enum reply { NORMAL, READ_ERROR, ZERO_BYTES, TRUNCATED_HEADER, HEADER_ONLY,
             OVERSIZED, NO_TERMINATOR, TERMINATOR_OUTSIDE_LENGTH };
struct process { pid_t pid; const char *path; enum reply reply; };
struct allocation { void *pointer; size_t capacity; bool live; };
static struct {
    struct process processes[16];
    size_t count;
    int argmax, argmaxResult;
    size_t argmaxLength, expectedCapacity;
    bool queryFails, listFails, listOversized, listEmpty;
    int failAllocation, allocationAttempts, allocationCount, freeCount;
    struct allocation allocations[4];
    int argmaxReads, listQueries, argumentReads, kills, killResult;
    int failKillIndex;
    pid_t killed[16];
    int signals[16];
} state;

static void assert_clean(void)
{
    assert(state.freeCount == state.allocationCount);
    for (int i = 0; i < state.allocationCount; i++) assert(!state.allocations[i].live);
}

static void reset(void)
{
    assert_clean();
    memset(&state, 0, sizeof(state));
    state.argmax = 8192;
    state.argmaxLength = sizeof(int);
    state.expectedCapacity = 8192;
}

static void add(pid_t pid, const char *path, enum reply reply)
{
    assert(state.count < sizeof(state.processes) / sizeof(state.processes[0]));
    state.processes[state.count++] = (struct process){ pid, path, reply };
}

static size_t capacity(void *pointer)
{
    for (int i = 0; i < state.allocationCount; i++) {
        if (state.allocations[i].pointer == pointer && state.allocations[i].live)
            return state.allocations[i].capacity;
    }
    assert(!"untracked or freed output buffer");
    return 0;
}

static void *mock_malloc(size_t size)
{
    if (++state.allocationAttempts == state.failAllocation) return NULL;
    assert(state.allocationCount < 4 && size > 0);
    void *pointer = malloc(size);
    assert(pointer);
    memset(pointer, 0xa5, size);
    state.allocations[state.allocationCount++] = (struct allocation){ pointer, size, true };
    return pointer;
}

static void mock_free(void *pointer)
{
    assert(pointer);
    (void)capacity(pointer);
    for (int i = 0; i < state.allocationCount; i++) {
        if (state.allocations[i].pointer == pointer && state.allocations[i].live) {
            state.allocations[i].live = false;
            state.freeCount++;
            free(pointer);
            return;
        }
    }
    assert(!"double free");
}

static int mock_sysctl(int *mib, unsigned int count, void *out, size_t *length,
                       void *input, size_t inputLength)
{
    assert(mib[0] == CTL_KERN && !input && inputLength == 0 && length);
    if (mib[1] == KERN_ARGMAX) {
        assert(count == 2 && out && *length == sizeof(int));
        state.argmaxReads++;
        memcpy(out, &state.argmax, sizeof(int));
        *length = state.argmaxLength;
        return state.argmaxResult;
    }
    if (mib[1] == KERN_PROC) {
        assert(count == 3 && mib[2] == KERN_PROC_ALL);
        if (!out) {
            state.listQueries++;
            *length = state.count * sizeof(struct kinfo_proc);
            return state.queryFails ? -1 : 0;
        }
        size_t available = capacity(out);
        assert(*length == available && available == state.count * sizeof(struct kinfo_proc));
        if (state.listFails) return -1;
        struct kinfo_proc *info = out;
        for (size_t i = 0; i < state.count; i++) info[i].kp_proc.p_pid = state.processes[i].pid;
        *length = state.listOversized ? available + 1 : (state.listEmpty ? 0 : available);
        return 0;
    }
    assert(mib[1] == KERN_PROCARGS2 && count == 3 && out && mib[2] > 0);
    size_t available = capacity(out);
    assert(*length == available && available == state.expectedCapacity);
    state.argumentReads++;
    for (size_t i = 0; i < state.count; i++) {
        struct process *process = &state.processes[i];
        if (process->pid != mib[2]) continue;
        if (process->reply == READ_ERROR) return -1;
        const int argc = 1;
        memcpy(out, &argc, sizeof(argc));
        if (process->reply == ZERO_BYTES || process->reply == TRUNCATED_HEADER ||
            process->reply == HEADER_ONLY) {
            *length = process->reply == ZERO_BYTES ? 0 :
                      process->reply == TRUNCATED_HEADER ? sizeof(int) - 1 : sizeof(int);
            return 0;
        }
        char *path = (char *)out + sizeof(int);
        if (process->reply == NO_TERMINATOR) {
            memset(path, 'x', available - sizeof(int));
            *length = available;
            return 0;
        }
        size_t used = sizeof(int) + strlen(process->path) + 1;
        assert(used <= available);
        memcpy(path, process->path, used - sizeof(int));
        *length = process->reply == OVERSIZED ? available + 1 :
                  process->reply == TERMINATOR_OUTSIDE_LENGTH ? used - 1 : used;
        return 0;
    }
    assert(!"unknown process");
    return -1;
}

static int mock_kill(pid_t pid, int signal)
{
    assert(pid > 0 && state.kills < 16);
    state.killed[state.kills] = pid;
    state.signals[state.kills++] = signal;
    errno = EPERM;
    return state.failKillIndex == state.kills ? -1 : state.killResult;
}

#define malloc mock_malloc
#define free mock_free
#define sysctl mock_sysctl
#define kill mock_kill
#include "killall-under-test.inc"
#undef malloc
#undef free
#undef sysctl
#undef kill

static int mock_execve(const char *path, char *const argv[], char *const env[])
{
    assert(strcmp(path, "/usr/bin/sbreload") == 0 && argv[0] == path && !argv[1] && !env);
    errno = ENOENT;
    return -1;
}
#define JBROOT_PATH(p) p
#define SIGTERM 15
#define execve mock_execve
static char **environ;
#include "respring-under-test.inc"
#undef execve

static void ordinary_paths(void)
{
    reset();
    add(0, NULL, NORMAL);
    add(-7, NULL, NORMAL);
    add(101, "/usr/libexec/backboardd", NORMAL);
    add(102, "/usr/libexec/backboardd-helper", NORMAL);
    add(103, "/tmp/backboardd", NORMAL);
    add(104, "/usr/libexec/backboardd", NORMAL);
    add(105, "/System/Library/TextInput/kbd", NORMAL);
    state.killResult = -1; /* A failed signal must not stop the remaining matches. */
    killall("/usr/libexec/backboardd", 15);
    assert(state.kills == 2 && state.killed[0] == 101 && state.killed[1] == 104);
    assert(state.signals[0] == 15 && state.signals[1] == 15);
    assert(state.argumentReads == 5 && state.allocationCount == 2);
    assert_clean();

    reset();
    state.argmax = 128;
    state.expectedCapacity = 128;
    add(201, "/System/Library/TextInput/kbd", NORMAL);
    add(202, "/usr/libexec/backboardd", NORMAL);
    killall("/System/Library/TextInput/kbd", 9);
    assert(state.kills == 1 && state.killed[0] == 201 && state.signals[0] == 9);
    assert_clean();
}

static void malformed_replies(void)
{
    reset();
    add(301, "/usr/libexec/backboardd", NORMAL);
    add(302, NULL, HEADER_ONLY); /* Must not reuse the preceding path. */
    add(303, NULL, ZERO_BYTES);
    add(304, NULL, TRUNCATED_HEADER);
    add(305, "/usr/libexec/backboardd", OVERSIZED);
    add(306, NULL, NO_TERMINATOR);
    add(307, "/usr/libexec/backboardd", TERMINATOR_OUTSIDE_LENGTH);
    add(308, NULL, READ_ERROR);
    add(309, "/usr/libexec/backboardd", NORMAL);
    killall("/usr/libexec/backboardd", 15);
    assert(state.argumentReads == 9 && state.kills == 2);
    assert(state.killed[0] == 301 && state.killed[1] == 309);
    assert_clean();

    reset();
    char edge[128 - sizeof(int)];
    memset(edge, 'e', sizeof(edge) - 1);
    edge[sizeof(edge) - 1] = '\0';
    state.argmax = 128;
    state.expectedCapacity = 128;
    add(401, edge, NORMAL);
    killall(edge, 9);
    assert(state.kills == 1 && state.killed[0] == 401);
    assert_clean();
}

static void invalid_capacity(void)
{
    for (int scenario = 0; scenario < 8; scenario++) {
        reset();
        state.expectedCapacity = 4096;
        if (scenario == 0) state.argmaxResult = -1;
        if (scenario == 1) state.argmax = 0;
        if (scenario == 2) state.argmax = -1;
        if (scenario == 3) state.argmax = (int)sizeof(int);
        if (scenario == 4) state.argmax = 1;
        if (scenario == 5) state.argmaxLength = 0;
        if (scenario == 6) state.argmaxLength = sizeof(int) - 1;
        if (scenario == 7) state.argmaxLength = sizeof(int) + 1;
        add(501, "/usr/libexec/backboardd", NORMAL);
        killall("/usr/libexec/backboardd", 15);
        assert(state.kills == 1 && state.argmaxReads == 1);
        assert_clean();
    }
}

static void failure_cleanup(void)
{
    reset();
    killall(NULL, 15);
    killall("", 15);
    assert(state.argmaxReads == 0 && state.listQueries == 0 && state.allocationAttempts == 0);
    for (int scenario = 0; scenario < 7; scenario++) {
        reset();
        if (scenario != 0) add(601, "/usr/libexec/backboardd", NORMAL);
        if (scenario == 1) state.queryFails = true;
        if (scenario == 2) state.listFails = true;
        if (scenario == 3) state.listOversized = true;
        if (scenario == 4) state.listEmpty = true;
        if (scenario == 5) state.failAllocation = 1;
        if (scenario == 6) state.failAllocation = 2;
        killall("/usr/libexec/backboardd", 15);
        assert(state.kills == 0 && state.argumentReads == 0);
        assert_clean();
    }
}

static void result_propagation(void)
{
    reset();
    assert(killall_with_result(NULL, 15) == EINVAL);
    assert(killall_with_result("", 15) == EINVAL);
    assert(respring_under_test() == ESRCH);
    assert_clean();

    reset();
    add(701, "/usr/libexec/backboardd", NORMAL);
    state.killResult = -1;
    assert(respring_under_test() == EPERM);
    assert_clean();

    reset();
    add(701, "/usr/libexec/backboardd", NORMAL);
    assert(respring_under_test() == 0);
    assert_clean();

    reset();
    add(701, "/usr/libexec/backboardd", NORMAL);
    add(702, "/usr/libexec/backboardd", NORMAL);
    state.failKillIndex = 1;
    assert(killall_with_result("/usr/libexec/backboardd", 15) == 0);
    assert(state.kills == 2);
    assert_clean();

    reset();
    add(701, "/usr/libexec/backboardd", NORMAL);
    add(702, "/usr/libexec/backboardd", NORMAL);
    state.failKillIndex = 2;
    assert(killall_with_result("/usr/libexec/backboardd", 15) == 0);
    assert(state.kills == 2);
    assert_clean();

    for (int scenario = 0; scenario < 4; scenario++) {
        reset();
        add(701, "/usr/libexec/backboardd", NORMAL);
        if (scenario == 0) state.queryFails = true;
        if (scenario == 1) state.listFails = true;
        if (scenario == 2) state.listOversized = true;
        if (scenario == 3) state.failAllocation = 2;
        errno = EIO;
        assert(respring_under_test() != 0);
        assert_clean();
    }
}

int main(void)
{
    ordinary_paths();
    malformed_replies();
    invalid_capacity();
    failure_cleanup();
    result_propagation();
    puts("killall capacity, path matching and cleanup C cases passed");
    return 0;
}
