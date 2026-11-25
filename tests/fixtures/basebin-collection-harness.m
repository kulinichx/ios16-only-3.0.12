#import <Foundation/Foundation.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
typedef uint8_t cdhash_t[20];
typedef struct { bool supported; } Fat;
typedef struct { uint32_t count; } trustcache_file_v1;
#define BASEBIN_TRUSTCACHE_UUID "test-only"
static unsigned hashes, builds, uploads, reallocations;
static unsigned failAllocation;
static int buildError, uploadError;
static Fat *fat_init_from_path(const char *path) {
    if (strstr(path,"malformed")) return NULL;
    Fat *fat = malloc(sizeof(*fat)); assert(fat);
    fat->supported = strstr(path,"unsupported") == NULL;
    return fat;
}
static void *fat_find_preferred_slice(Fat *fat) { return fat->supported ? fat : NULL; }
static void fat_free(Fat *fat) { free(fat); }
static int ensure_randomized_cdhash(const char *path, cdhash_t hash) {
    hashes++;
    if (strstr(path,"unsigned")) return -1;
    memset(hash, hashes, sizeof(cdhash_t));
    return 0;
}
static int trustcache_file_build_from_cdhashes(cdhash_t *input, uint32_t count, trustcache_file_v1 **out) {
    assert(input && count); builds++;
    if (buildError) return buildError;
    *out = malloc(sizeof(**out)); assert(*out); (*out)->count = count;
    return 0;
}
static int trustcache_file_upload_with_uuid(trustcache_file_v1 *file, const char *uuid) {
    assert(file && !strcmp(uuid,BASEBIN_TRUSTCACHE_UUID)); uploads++;
    assert(file->count == hashes);
    return uploadError;
}
static void *test_realloc(void *p, size_t size) {
    if (++reallocations == failAllocation) return NULL;
    return realloc(p,size);
}
#define realloc test_realloc
/* PRODUCTION_BASEBIN */
#undef realloc

static void add(NSString *directory, NSString *name, bool macho) {
    uint32_t marker = macho ? MH_MAGIC_64 : 0;
    NSData *data = [NSData dataWithBytes:&marker length:sizeof(marker)];
    assert([data writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
}
static void reset(NSString *directory) {
    [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
    assert([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    hashes = builds = uploads = reallocations = 0;
    failAllocation = 0; buildError = uploadError = 0;
}
int main(int argc, const char **argv) {
    assert(argc == 2);
    @autoreleasepool {
        NSString *dir = @(argv[1]);
        reset(dir); add(dir,@"resource",false); add(dir,@"a.dylib",true); add(dir,@"b.dylib",true);
        assert(symlink("a.dylib",[dir stringByAppendingPathComponent:@"alias"].fileSystemRepresentation) == 0);
        assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) == 0);
        assert(hashes == 2 && builds == 1 && uploads == 1);
        for (NSString *bad in @[@"unsigned.dylib",@"malformed.dylib"]) {
            reset(dir); add(dir,@"good.dylib",true); add(dir,bad,true);
            assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) != 0);
            assert(builds == 0 && uploads == 0);
        }
        reset(dir); add(dir,@"unsupported.dylib",true); add(dir,@"good.dylib",true);
        assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) == 0 && hashes == 1);
        for (unsigned n = 1; n <= 2; n++) {
            reset(dir); add(dir,@"a",true); add(dir,@"b",true); failAllocation=n;
            assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) != 0 && builds == 0 && uploads == 0);
        }
        reset(dir); add(dir,@"good",true); buildError=-7;
        assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) == -7 && uploads == 0);
        reset(dir); add(dir,@"good",true); uploadError=-8;
        assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) == -8 && uploads == 1);
        reset(dir); add(dir,@"resource",false);
        assert(randomizeAndLoadBasebinTrustcache(dir.fileSystemRepresentation) != 0 && hashes == 0 && uploads == 0);
        assert(randomizeAndLoadBasebinTrustcache(NULL) != 0);
        assert(randomizeAndLoadBasebinTrustcache([dir stringByAppendingPathComponent:@"missing"].fileSystemRepresentation) != 0);
    }
    puts("PASS real basebin enumeration: resources, host slice, malformed/signing/allocation/build/upload failures");
}
