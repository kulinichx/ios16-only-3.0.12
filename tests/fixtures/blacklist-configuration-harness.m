#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdlib.h>
#undef assert
#define assert(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "fixture regression: blacklist line %d\n", __LINE__); _Exit(86); } } while (0)
static NSString *root;
static NSString *JBROOT_PATH(NSString *path) { return [root stringByAppendingString:path]; }
static NSSet *builtinApps(void) { return [NSSet setWithObject:@"cn.zqbb.dopaRH"]; }
static NSString *getAppBundlePathFromSpawnPath(const char *path) { return path ? @(path) : nil; }
/* PRODUCTION_CONFIGURATION */
static void writePlist(id value, NSString *path) {
    assert([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil]);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    assert(data && [data writeToFile:path atomically:YES]);
}
int main(int argc, char **argv) {
    assert(argc == 2);
    @try {
    @autoreleasepool {
        root = @(argv[1]);
        NSString *config = JBROOT_PATH(@"/var/mobile/Library/RootHide/RootHideConfig.plist");
        NSString *wants = JBROOT_PATH(@"/var/mobile/Library/RootHide/cn.zqbb.inject.wantsblacklist.plist");
        NSArray *values = @[@YES, @NO, @1, @0, @(-1), @"YES", @"NO", @"true", @"false", @"1", @"0", @[], @{}, NSDate.date, [NSData data]];
        for (id value in values) {
            BOOL expected = ([value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class]) && [value boolValue];
            writePlist(@{@"appconfig": @{@"org.example.app": value}}, config);
            writePlist(@{@"Example": value}, wants);
            assert(isBlacklistedApp("org.example.app") == expected);
            assert(zqbb_wantsBlacklist(@"Example") == expected);
            assert(!isBlacklistedApp("cn.zqbb.dopaRH"));
        }
        for (id section in @[@[], @"bad", @42, NSDate.date]) {
            writePlist(@{@"appconfig": section}, config);
            assert(!isBlacklistedApp("org.example.app"));
        }
        writePlist(@[], config); writePlist(@[], wants);
        assert(!isBlacklistedApp("org.example.app") && !zqbb_wantsBlacklist(@"Example"));
        assert(!isBlacklistedApp(NULL) && !isBlacklistedApp("") && !isBlacklistedApp("\xff"));
        assert(!zqbb_wantsBlacklist(nil));
        NSString *bundle = [root stringByAppendingPathComponent:@"Example.app"];
        NSString *info = [bundle stringByAppendingPathComponent:@"Info.plist"];
        for (id identifier in @[@42, @[], @{}, @""]) {
            writePlist(@{@"CFBundleIdentifier": identifier}, info);
            assert(!getAppIdentifierFromPath(bundle.fileSystemRepresentation));
        }
        writePlist(@{@"CFBundleIdentifier": @"org.example.app"}, info);
        assert([getAppIdentifierFromPath(bundle.fileSystemRepresentation) isEqual:@"org.example.app"]);
        [NSFileManager.defaultManager removeItemAtPath:config error:nil];
        assert(!isBlacklistedApp("org.example.app"));
    }
    } @catch (NSException *exception) {
        fprintf(stderr, "fixture regression: blacklist exception %s\n", exception.name.UTF8String);
        return 86;
    }
    puts("PASS production blacklist: scalar compatibility, malformed plist sections and bundle identifiers");
}
