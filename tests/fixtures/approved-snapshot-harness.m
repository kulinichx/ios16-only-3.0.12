#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>

static NSString *testRoot;
static NSString * const stockRoot = @"/var/mobile/Library/SplashBoard/Snapshots/";
static unsigned originalCalls;
static bool is_apple_internal_identifier(const char *identifier) {
    return identifier && !strcmp(identifier, "com.apple.test-internal");
}
static NSString *jbroot(NSString *path) { return [testRoot stringByAppendingString:path]; }

@interface XBSnapshotContainerIdentity : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *originalPath;
@property (nonatomic, readonly, copy) NSString *snapshotContainerPath;
@end
@implementation XBSnapshotContainerIdentity
/* PRODUCTION_CONTAINER_PATH */
@end

@interface XBApplicationSnapshot : NSObject
@property (nonatomic, strong) XBSnapshotContainerIdentity *containerIdentity;
@property (nonatomic, copy) NSString *destination;
@property (nonatomic) long long lastFormat;
- (NSString *)_configureDefaultPathWithinGroupForFormat:(long long)format;
@end
@implementation XBApplicationSnapshot
- (NSString *)_configureDefaultPathWithinGroupForFormat:(long long)format {
    self.lastFormat = format;
    return self.destination;
}
@end

@interface XBApplicationSnapshotManifestImpl : NSObject
+ (long long)_outputFormatForSnapshot:(XBApplicationSnapshot *)snapshot;
- (BOOL)originalSaveData:(NSData *)data forSnapshot:(XBApplicationSnapshot *)snapshot;
- (BOOL)_imageAccessQueue_saveData:(NSData *)data forSnapshot:(XBApplicationSnapshot *)snapshot;
@end
@implementation XBApplicationSnapshotManifestImpl
+ (long long)_outputFormatForSnapshot:(XBApplicationSnapshot *)snapshot {
    assert(snapshot != nil);
    return 57;
}
- (BOOL)originalSaveData:(NSData *)data forSnapshot:(XBApplicationSnapshot *)snapshot {
    (void)data; (void)snapshot;
    originalCalls++;
    return YES;
}
/* PRODUCTION_SAVE */
@end

int main(void) {
    @autoreleasepool {
        testRoot = [NSTemporaryDirectory().stringByResolvingSymlinksInPath stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *snapshotRoot = jbroot(stockRoot);
        XBSnapshotContainerIdentity *identity = [XBSnapshotContainerIdentity new];
        identity.bundleIdentifier = @"org.test.app";
        identity.originalPath = [stockRoot stringByAppendingString:@"org.test.app"];
        XBApplicationSnapshot *snapshot = [XBApplicationSnapshot new];
        snapshot.containerIdentity = identity;
        snapshot.destination = [snapshotRoot stringByAppendingString:@"new/sub/image.png"];
        XBApplicationSnapshotManifestImpl *manifest = [XBApplicationSnapshotManifestImpl new];
        NSData *data = [@"snapshot-test-bytes" dataUsingEncoding:NSUTF8StringEncoding];
        assert([identity.snapshotContainerPath isEqual:jbroot(identity.originalPath)]);
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        assert([[NSData dataWithContentsOfFile:snapshot.destination] isEqual:data]);
        assert(snapshot.lastFormat == 57 && originalCalls == 0);

        identity.bundleIdentifier = @"com.apple.stock";
        assert([identity.snapshotContainerPath isEqual:identity.originalPath]);
        unsigned count = originalCalls;
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        assert(originalCalls == count + 1);

        identity.bundleIdentifier = @"com.apple.test-internal";
        snapshot.destination = [snapshotRoot stringByAppendingString:@"internal/image.png"];
        count = originalCalls;
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        assert([[NSData dataWithContentsOfFile:snapshot.destination] isEqual:data]);
        assert(originalCalls == count);
        identity.bundleIdentifier = @"org.test.app";

        count = originalCalls;
        assert([manifest _imageAccessQueue_saveData:[NSData data] forSnapshot:snapshot]);
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:nil]);
        snapshot.containerIdentity = nil;
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        snapshot.containerIdentity = identity;
        identity.bundleIdentifier = nil;
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        identity.bundleIdentifier = @"";
        assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        assert(originalCalls == count + 5);
        identity.bundleIdentifier = @"org.test.app";

        count = originalCalls;
        for (NSString *outside in @[@"/other/container", @"/var/mobile/Library/SplashBoard/Snapshots-other/app"]) {
            identity.originalPath = outside;
            assert([identity.snapshotContainerPath isEqual:outside]);
            assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        }
        assert(originalCalls == count + 2);
        identity.originalPath = [stockRoot stringByAppendingString:@"org.test.app"];

        count = originalCalls;
        NSArray *destinations = @[
            [testRoot stringByAppendingPathComponent:@"elsewhere.png"],
            [snapshotRoot stringByAppendingString:@"../escaped.png"],
            [[snapshotRoot substringToIndex:snapshotRoot.length - 1] stringByAppendingString:@"-other/image.png"]
        ];
        for (NSString *destination in destinations) {
            snapshot.destination = destination;
            assert([manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
            assert(![fm fileExistsAtPath:destination.stringByStandardizingPath]);
        }
        assert(originalCalls == count + destinations.count);

        count = originalCalls;
        snapshot.destination = nil;
        assert(![manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        snapshot.destination = [snapshotRoot stringByAppendingString:@"directory"];
        assert([fm createDirectoryAtPath:snapshot.destination withIntermediateDirectories:YES attributes:nil error:nil]);
        assert(![manifest _imageAccessQueue_saveData:data forSnapshot:snapshot]);
        assert(originalCalls == count);
        assert([fm removeItemAtPath:testRoot error:nil]);
        puts("PASS approved snapshot routing: real temporary-file writes, stock/internal apps, fallback and failures");
    }
    return 0;
}
