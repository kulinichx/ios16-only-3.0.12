#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xpc/xpc.h>
#include "_configuration.h"

static char configPath[PATH_MAX];
static const char *test_path(const char *path)
{
    return strcmp(path, "/basebin/config.plist") == 0 ? configPath : "/nonexistent-rh-test-inject.plist";
}
#define JBROOT_PATH(path) test_path(path)
typedef enum { kSpawnConfigInject = 1, kSpawnConfigTrust = 2 } kSpawnConfig;
static bool zqbb_wantInject(const char *name, const char *path) { (void)name; (void)path; return false; }
static bool zqbb_isWhiteList(const char *path) { (void)path; return false; }

/* PRODUCTION_INPUTS */

static void replace_config(const char *value)
{
    char temp[PATH_MAX];
    assert(snprintf(temp, sizeof(temp), "%s.tmp", configPath) < (int)sizeof(temp));
    FILE *file = fopen(temp, "w");
    assert(file);
    assert(fprintf(file, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>"
        "<key>ProcessBlacklist</key><array><integer>42</integer><string>%s</string></array>"
        "</dict></plist>", value) > 0);
    assert(fclose(file) == 0);
    // A replacement with the same timestamp must still be seen on the next call.
    const struct timespec times[2] = {{1000000000, 0}, {1000000000, 0}};
    assert(utimensat(AT_FDCWD, temp, times, 0) == 0);
    assert(rename(temp, configPath) == 0);
}

static void *read_config(void *unused)
{
    (void)unused;
    for (unsigned i = 0; i < 500; i++) {
        xpc_object_t array = jbuserconfig_copy_value("ProcessBlacklist");
        assert(array && xpc_get_type(array) == XPC_TYPE_ARRAY);
        const char *path = xpc_array_get_string(array, 1);
        assert(path && (!strcmp(path, "/test/A") || !strcmp(path, "/test/B")));
        // Another read/replacement must not invalidate the value still in use.
        (void)spawn_config_for_executable("/test/A", NULL);
        assert(!strcmp(path, "/test/A") || !strcmp(path, "/test/B"));
        xpc_release(array);
    }
    return NULL;
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    assert(snprintf(configPath, sizeof(configPath), "%s/config.plist", argv[1]) < (int)sizeof(configPath));
    __block unsigned outer = 0, inner = 0;
    static const char *expected[] = {"A", "B", "C"};
    char caller[] = "left:right";
    assert(!strcmp(strtok(caller, ":"), "left"));
    string_enumerate_components("A:B:C", ":", ^(const char *part, bool *stop) {
        (void)stop;
        assert(outer < 3 && !strcmp(part, expected[outer++]));
        string_enumerate_components("1:2", ":", ^(const char *nested, bool *nestedStop) {
            (void)nestedStop;
            assert(!strcmp(nested, inner % 2 == 0 ? "1" : "2"));
            inner++;
        });
    });
    assert(outer == 3 && inner == 6);
    assert(!strcmp(strtok(NULL, ":"), "right"));
    __block unsigned stopped = 0;
    string_enumerate_components("A:B", ":", ^(const char *part, bool *stop) {
        (void)part; stopped++; *stop = true;
    });
    assert(stopped == 1);

    replace_config("/test/A");
    xpc_object_t saved = jbuserconfig_copy_value("ProcessBlacklist");
    assert(saved);
    assert(spawn_config_for_executable("/test/A", NULL) == kSpawnConfigTrust);
    replace_config("/test/B");
    assert(spawn_config_for_executable("/test/A", NULL) == (kSpawnConfigInject | kSpawnConfigTrust));
    assert(spawn_config_for_executable("/test/B", NULL) == kSpawnConfigTrust);
    assert(!strcmp(xpc_array_get_string(saved, 1), "/test/A"));
    xpc_release(saved);

    pthread_t readers[4];
    for (unsigned i = 0; i < 4; i++) assert(pthread_create(&readers[i], NULL, read_config, NULL) == 0);
    for (unsigned i = 0; i < 200; i++) replace_config(i % 2 ? "/test/A" : "/test/B");
    for (unsigned i = 0; i < 4; i++) assert(pthread_join(readers[i], NULL) == 0);

    assert(unlink(configPath) == 0);
    assert(jbuserconfig_copy_value("ProcessBlacklist") == NULL);
    FILE *empty = fopen(configPath, "w"); assert(empty); assert(fclose(empty) == 0);
    for (unsigned i = 0; i < 1000; i++) assert(jbuserconfig_copy_value("ProcessBlacklist") == NULL);
    assert(spawn_config_for_executable("/test/A", NULL) == (kSpawnConfigInject | kSpawnConfigTrust));
    puts("production spawn input reentry, replacement and concurrent ownership passed");
    return 0;
}
