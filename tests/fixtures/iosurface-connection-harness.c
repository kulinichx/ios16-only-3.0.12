#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef unsigned int io_service_t;
typedef unsigned int io_connect_t;
typedef int kern_return_t;
#define KERN_SUCCESS 0
#define JBLogDebug(...) ((void)0)

static io_service_t service = 17;
static io_connect_t connection;
static unsigned int lookups, opens, closes;
static const char *scenario;

static unsigned int mach_task_self(void) { return 123; }

static void *litehook_find_dsc_symbol(const char *image, const char *symbol)
{
    assert(!strcmp(image, "/System/Library/Frameworks/IOSurface.framework/IOSurface"));
    assert(opens == 0 && closes == 0);
    lookups++;
    if (!strcmp(symbol, "__iosService")) {
        assert(lookups == 1);
        return !strcmp(scenario, "missing-service") ? NULL : &service;
    }
    assert(!strcmp(symbol, "__iosConnect") && lookups == 2);
    return !strcmp(scenario, "missing-connection") ? NULL : &connection;
}

static kern_return_t IOServiceOpen(io_service_t input, unsigned int task,
    unsigned int type, io_connect_t *output)
{
    assert(lookups == 2 && input == service && task == 123 && type == 0);
    assert(output == &connection && connection == 41 && closes == 0);
    opens++;
    if (!strcmp(scenario, "open-failure")) return 5;
    *output = 42;
    return KERN_SUCCESS;
}

static kern_return_t IOServiceClose(io_connect_t input)
{
    assert(opens == 1 && input == 41 && connection == 42);
    closes++;
    return KERN_SUCCESS;
}

/* PRODUCTION_FUNCTION */

int main(int argc, char **argv)
{
    assert(argc == 2);
    scenario = argv[1];
    connection = !strcmp(scenario, "inactive") ? 0 : 41;
    fix__iosConnect();
    assert(lookups == 2);
    if (!strcmp(scenario, "inactive")) {
        assert(connection == 0 && opens == 0 && closes == 0);
    } else {
        assert(!strcmp(scenario, "active"));
        assert(connection == 42 && opens == 1 && closes == 1);
    }
    puts("IOSurface connection checks passed");
    return 0;
}
