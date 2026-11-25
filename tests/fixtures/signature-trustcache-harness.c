// Execute the production classification and append functions against synthetic
// Mach-O headers and fake kernel pages. No kernel access or real files are used.
#include <assert.h>
#include <dispatch/dispatch.h>
#include <mach/machine.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <alloca.h>

#ifdef CPU_SUBTYPE_ARM64E_ABI_V2
#undef CPU_SUBTYPE_ARM64E_ABI_V2
#endif
#define CPU_SUBTYPE_ARM64E_ABI_V2 ((cpu_subtype_t)0x80000000)
#define CS_CDHASH_LEN 20
/* PRODUCTION_STRUCTS */

typedef struct { struct mach_header header; } MachO;
static cpu_subtype_t fakeHostSubtype;
static unsigned hostQueries;
static void host_get_cpu_information(cpu_type_t *type, cpu_subtype_t *subtype)
{
    hostQueries++;
    *type = CPU_TYPE_ARM64;
    *subtype = fakeHostSubtype;
}
static struct mach_header *macho_get_mach_header(MachO *macho) { return &macho->header; }

/* PRODUCTION_MAPPABLE */

#define MAX_PAGES 8
static unsigned char pages[MAX_PAGES][JB_TRUSTCACHE_SIZE];
static size_t pageCount, reads, writes;
static bool failGrow, failRead, failWrite;
static uint64_t pageAddress(size_t page) { return 0x100000000ULL + page * JB_TRUSTCACHE_SIZE; }
static void *kernelPointer(uint64_t address, size_t size)
{
    assert(address >= pageAddress(0));
    uint64_t offset = address - pageAddress(0);
    assert(offset < pageCount * JB_TRUSTCACHE_SIZE);
    assert(size <= JB_TRUSTCACHE_SIZE - offset % JB_TRUSTCACHE_SIZE);
    return pages[offset / JB_TRUSTCACHE_SIZE] + offset % JB_TRUSTCACHE_SIZE;
}
static uint32_t kread32(uint64_t address)
{
    uint32_t value;
    memcpy(&value, kernelPointer(address, sizeof(value)), sizeof(value));
    reads++;
    return value;
}
static int kreadbuf(uint64_t address, void *output, size_t size)
{
    if (failRead) return -1;
    memcpy(output, kernelPointer(address, size), size);
    reads++;
    return 0;
}
static int kwritebuf(uint64_t address, const void *input, size_t size)
{
    if (failWrite) return -1;
    memcpy(kernelPointer(address, size), input, size);
    writes++;
    return 0;
}
static void _jb_trustcache_enumerate(void (^block)(uint64_t, bool *))
{
    for (size_t page = 0; page < pageCount; page++) {
        bool stop = false;
        block(pageAddress(page), &stop);
        if (stop) break;
    }
}
static uint64_t _jb_trustcache_grow(void)
{
    if (failGrow) return 0;
    assert(pageCount < MAX_PAGES);
    memset(pages[pageCount], 0, JB_TRUSTCACHE_SIZE);
    return pageAddress(pageCount++);
}
static int compareEntries(const void *left, const void *right)
{
    return memcmp(left, right, sizeof(trustcache_entry_v1));
}
static void _trustcache_file_sort(trustcache_file_v1 *file)
{
    assert(file->length <= JB_TRUSTCACHE_ENTRY_COUNT);
    qsort(file->entries, file->length, sizeof(trustcache_entry_v1), compareEntries);
}

/* PRODUCTION_APPEND */
/* PRODUCTION_ADD_CDHASHES */

static trustcache_entry_v1 entryFor(uint32_t identifier)
{
    trustcache_entry_v1 entry = {0};
    memcpy(entry.hash, &identifier, sizeof(identifier));
    entry.hash_type = 1;
    entry.flags = (uint8_t)(identifier % 2);
    return entry;
}
static void checkAppend(const size_t *initialLengths, size_t initialPages, size_t added)
{
    pageCount = reads = writes = 0;
    size_t initialCount = 0;
    uint32_t identifier = 1;
    for (size_t page = 0; page < initialPages; page++) {
        _jb_trustcache_grow();
        jb_trustcache *cache = (jb_trustcache *)pages[page];
        assert(initialLengths[page] <= JB_TRUSTCACHE_ENTRY_COUNT);
        cache->file.length = (uint32_t)initialLengths[page];
        for (size_t i = 0; i < initialLengths[page]; i++) cache->file.entries[i] = entryFor(identifier++);
        initialCount += initialLengths[page];
    }
    trustcache_entry_v1 *input = calloc(added ? added : 1, sizeof(*input));
    trustcache_entry_v1 *expected = calloc(initialCount + added + 1, sizeof(*expected));
    trustcache_entry_v1 *actual = calloc(initialCount + added + 1, sizeof(*actual));
    assert(input && expected && actual);
    for (size_t i = 0; i < added; i++) input[i] = entryFor(identifier++);
    for (size_t i = 0; i < initialCount + added; i++) expected[i] = entryFor((uint32_t)i + 1);
    assert(jb_trustcache_add_entries(added ? input : NULL, (uint32_t)added) == 0);
    if (!added) assert(reads == 0 && writes == 0 && pageCount == initialPages);
    size_t count = 0;
    for (size_t page = 0; page < pageCount; page++) {
        jb_trustcache *cache = (jb_trustcache *)pages[page];
        assert(cache->file.length <= JB_TRUSTCACHE_ENTRY_COUNT);
        assert(count + cache->file.length <= initialCount + added);
        memcpy(actual + count, cache->file.entries, cache->file.length * sizeof(*actual));
        count += cache->file.length;
    }
    assert(count == initialCount + added);
    qsort(actual, count, sizeof(*actual), compareEntries);
    qsort(expected, count, sizeof(*expected), compareEntries);
    assert(memcmp(actual, expected, count * sizeof(*actual)) == 0);
    for (size_t i = 0; i < added; i++) {
        trustcache_entry_v1 original = entryFor((uint32_t)(initialCount + i + 1));
        assert(memcmp(&input[i], &original, sizeof(original)) == 0);
    }
    free(input); free(expected); free(actual);
}
static void checkArchitecture(cpu_subtype_t host)
{
    fakeHostSubtype = host;
    bool hostIsArm64e = (host & 0x00ffffff) == CPU_SUBTYPE_ARM64E;
    const cpu_subtype_t subtypes[] = {CPU_SUBTYPE_ARM64_ALL, CPU_SUBTYPE_ARM64_V8,
        CPU_SUBTYPE_ARM64E, (cpu_subtype_t)(CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2)};
    const uint32_t filetypes[] = {MH_EXECUTE, MH_DYLIB, MH_BUNDLE};
    for (size_t i = 0; i < sizeof(subtypes) / sizeof(*subtypes); i++) {
        for (size_t j = 0; j < sizeof(filetypes) / sizeof(*filetypes); j++) {
            MachO macho = {.header = {.cputype = CPU_TYPE_ARM64, .cpusubtype = subtypes[i], .filetype = filetypes[j]}};
            bool expected = i < 2 || (hostIsArm64e && (i == 3 || filetypes[j] != MH_EXECUTE));
            assert(macho_is_mappable(&macho) == expected);
        }
    }
    MachO other = {.header = {.cputype = CPU_TYPE_X86_64, .cpusubtype = CPU_SUBTYPE_ARM64_ALL, .filetype = MH_DYLIB}};
    assert(!macho_is_mappable(&other));
    assert(hostQueries == 1);
}
int main(int argc, const char *argv[])
{
    assert(argc == 2);
    if (!strcmp(argv[1], "arm64e")) checkArchitecture(CPU_SUBTYPE_ARM64E);
    else if (!strcmp(argv[1], "arm64e-capability"))
        checkArchitecture((cpu_subtype_t)(CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2));
    else if (!strcmp(argv[1], "arm64")) checkArchitecture(CPU_SUBTYPE_ARM64_ALL);
    else {
        assert(!strcmp(argv[1], "append"));
        const size_t nearFull[] = {JB_TRUSTCACHE_ENTRY_COUNT - 1};
        const size_t full[] = {JB_TRUSTCACHE_ENTRY_COUNT};
        const size_t partial[] = {JB_TRUSTCACHE_ENTRY_COUNT - 1, JB_TRUSTCACHE_ENTRY_COUNT - 2};
        checkAppend(NULL, 0, 0);
        checkAppend(full, 1, 0);
        checkAppend(NULL, 0, 1);
        checkAppend(NULL, 0, JB_TRUSTCACHE_ENTRY_COUNT);
        checkAppend(NULL, 0, JB_TRUSTCACHE_ENTRY_COUNT + 3);
        checkAppend(nearFull, 1, 2);
        checkAppend(full, 1, 2 * JB_TRUSTCACHE_ENTRY_COUNT + 3);
        checkAppend(partial, 2, 5);
        trustcache_entry_v1 entry = entryFor(42);
        pageCount = reads = writes = 0;
        assert(jb_trustcache_add_entries(NULL, 1) != 0);
        assert(jb_trustcache_add_cdhashes(NULL, 1) != 0);
        assert(jb_trustcache_add_cdhashes(NULL, 0) == 0);
        assert(reads == 0 && writes == 0 && pageCount == 0);
        failGrow = true;
        assert(jb_trustcache_add_entries(&entry, 1) != 0);
        assert(reads == 0 && writes == 0 && pageCount == 0);
        failGrow = false;
        _jb_trustcache_grow();
        failRead = true;
        assert(jb_trustcache_add_entries(&entry, 1) != 0);
        assert(writes == 0);
        failRead = false;
        failWrite = true;
        assert(jb_trustcache_add_entries(&entry, 1) != 0);
        assert(((jb_trustcache *)pages[0])->file.length == 0);
        failWrite = false;
        cdhash_t hashes[2] = {{1}, {2}};
        assert(jb_trustcache_add_cdhashes(hashes, 2) == 0);
        assert(((jb_trustcache *)pages[0])->file.length == 2);
    }
    puts("PASS production classification/trustcache regression");
    return 0;
}
