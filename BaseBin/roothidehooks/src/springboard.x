#import <Foundation/Foundation.h>
#include <roothide.h>
#include "common.h"

@interface XBSnapshotContainerIdentity : NSObject
@property NSString* bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *snapshotContainerPath;
@end

@interface XBApplicationSnapshot : NSObject
- (XBSnapshotContainerIdentity *)containerIdentity;
- (NSString *)_configureDefaultPathWithinGroupForFormat:(long long)format;
@end

@interface XBApplicationSnapshotManifestImpl : NSObject
+ (long long)_outputFormatForSnapshot:(id)snapshot;
@end

%hook XBSnapshotContainerIdentity

/*
-(id)_initWithBundleIdentifier:(id)arg1 bundlePath:(id)arg2 dataContainerPath:(id)arg3 bundleContainerPath:(id)arg4 
{
    NSLog(@"snapshot init, id=%@, bundlePath=%@, dataContainerPath=%@, bundleContainerPath=%@", arg1, arg2, arg3, arg4);

    return %orig;
}
*/

-(NSString *)snapshotContainerPath {
    NSString* path = %orig;

    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && (![self.bundleIdentifier hasPrefix:@"com.apple."] || is_apple_internal_identifier(self.bundleIdentifier.UTF8String))) {
        NSLog(@"snapshotContainerPath redirect %@ : %@", self.bundleIdentifier, path);
        path = jbroot(path);
    }

    return path;
}

%end

%hook XBApplicationSnapshotManifestImpl

- (BOOL)_imageAccessQueue_saveData:(NSData *)data forSnapshot:(XBApplicationSnapshot *)snapshot
{
	if (!data.length || !snapshot) {
		return %orig;
	}

	XBSnapshotContainerIdentity *ident = snapshot.containerIdentity;
	NSString *bundleIdentifier = ident.bundleIdentifier;
	NSString *snapshotRoot = [jbroot(@"/var/mobile/Library/SplashBoard/Snapshots")
		stringByAppendingString:@"/"];
	// Keep RootHide's existing exception for Apple-internal jailbreak apps.
	BOOL isStockAppleApp = [bundleIdentifier hasPrefix:@"com.apple."] &&
		!is_apple_internal_identifier(bundleIdentifier.UTF8String);
	if (!bundleIdentifier.length || isStockAppleApp ||
		![ident.snapshotContainerPath hasPrefix:snapshotRoot]) {
		return %orig;
	}

	NSString *path = [snapshot _configureDefaultPathWithinGroupForFormat:
		[[self class] _outputFormatForSnapshot:snapshot]];
	if (!path) {
		return NO;
	}
	if (![path.stringByStandardizingPath hasPrefix:snapshotRoot]) {
		return %orig;
	}

	[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
						  withIntermediateDirectories:YES attributes:nil error:nil];
	return [data writeToFile:path options:0 error:nil];
}

%end

static const void *kDenyQueryTagKey = &kDenyQueryTagKey;

%hook FBSApplicationLibrary
-(id)applicationInfoForBundleIdentifier:(NSString*)bundleIdentifier
{
	id result = %orig; //SBApplicationInfo
	NSURL* executableURL = [result performSelector:@selector(executableURL)];
	NSLog(@"FBSApplicationLibrary applicationInfoForBundleIdentifier %@ : %@, %@", bundleIdentifier, result, executableURL);

	NSNumber* tag = objc_getAssociatedObject(bundleIdentifier, kDenyQueryTagKey);

	if(tag && tag.boolValue) {

		if(is_sensitive_app_identifier(bundleIdentifier.UTF8String)) {
			NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
			return nil;
		}

		if(result && executableURL && isLikelyJailbrokenBundlePath(executableURL.path.fileSystemRepresentation)) {
			NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
			return nil;
		}
	}

	return result;
}
%end

%hook FBSystemService
-(void*)openApplication:(NSString*)bundleIdentifier withOptions:(id)options originator:(id)originator requestID:(void*)requestID completion:(void*)completion
{
	NSLog(@"openApplication %@ withOptions:%@ originator:%@ requestID:%@ completion:%p", bundleIdentifier, options, originator, requestID, completion);

	id currentContext = [NSClassFromString(@"BSServiceConnection") performSelector:@selector(currentContext)];
	id remoteProcess = [currentContext performSelector:@selector(remoteProcess)]; //BSProcessHandle

	NSNumber* _pid = [remoteProcess valueForKey:@"_pid"];
	NSString* _bundleID = [remoteProcess valueForKey:@"_bundleID"]; //may be nil

	pid_t pid = _pid.intValue;

	NSLog(@"openApplication %@ from pid=%d bundleID=%@", bundleIdentifier, pid, _bundleID);

	if(jbclient_blacklist_check_pid(pid)==true) {
		NSLog(@"openApplication deny request from %@", _bundleID);
		objc_setAssociatedObject(bundleIdentifier, kDenyQueryTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	return %orig;
}
%end

void sbInit(void)
{
	NSLog(@"sbInit...");
	%init();
	extern void rcLowPowerScheduleStart(void);
	rcLowPowerScheduleStart();
}
