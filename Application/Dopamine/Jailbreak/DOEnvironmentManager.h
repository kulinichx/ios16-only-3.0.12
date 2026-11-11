//
//  EnvironmentManager.h
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import <Foundation/Foundation.h>
#import "DOBootstrapper.h"

NS_ASSUME_NONNULL_BEGIN

@interface DOEnvironmentManager : NSObject
{
    DOBootstrapper *_bootstrapper;
    BOOL _isJailbroken;
    NSString *_jailbrokenVersion;
    BOOL _bootstrapNeedsMigration;
}

+ (instancetype)sharedManager;

- (NSString *)appVersion;
- (NSString *)appVersionDisplayString;
- (NSString *)nightlyHash;

- (NSString *)privatePrebootPath;
- (NSString *)activePrebootPath;

- (BOOL)isInstalledThroughTrollStore;
- (BOOL)isJailbroken;
- (BOOL)isJailbrokenWithOtherJailbreak;
- (BOOL)isBootstrapped;
- (NSString *)jailbrokenVersion;
- (NSString *)jailbrokenVersionRootHide;
- (NSString *)systemVersion;

- (BOOL)isSupported;
- (BOOL)isArm64e;
- (NSString *)versionSupportString;
- (NSString *)accessibleKernelPath;
- (void)locateJailbreakRoot;
- (NSError *)ensureJailbreakRootExists;

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version;

- (void)runUnsandboxed:(void (^)(void))unsandboxBlock;
- (void)runAsRoot:(void (^)(void))rootBlock;

- (int)respring;
- (int)rebootUserspace;
- (void)rebuildIconCache;
- (void)refreshJailbreakApps;
- (NSString *)injectionModeDescription;
- (NSString *)sileoURLScheme;
- (int)reboot;
- (void)changeMobilePassword:(NSString *)newPassword;
- (NSError*)updateEnvironment;
- (void)updateJailbreakFromTIPA:(NSString *)tipaPath;

- (BOOL)isTweakInjectionEnabled;
- (void)setTweakInjectionEnabled:(BOOL)enabled;
- (BOOL)isIDownloadEnabled;
- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox;
- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox;
/*
- (BOOL)isFakelibMounted;
- (int)setFakelibMounted:(BOOL)mounted;
- (int)setPrivatePrebootProtected:(BOOL)protected;
- (BOOL)isJailbreakHidden;
- (void)setJailbreakHidden:(BOOL)hidden;
*/

- (BOOL)isPACBypassRequired;
- (BOOL)isPPLBypassRequired;

- (NSError *)prepareBootstrap;
- (NSError *)finalizeBootstrap;
- (NSError *)deleteBootstrap;
- (NSError *)reinstallPackageManagers;
- (NSError *)updateBootLogo;
- (NSArray<NSString *> *)customMountPaths;
// Startup restoration must finish before the jailbreak continues.
- (int)mountCustomDirectory:(NSString *)path;
- (void)mountCustomDirectory:(NSString *)path completion:(void (^)(int result))completion;
- (void)unmountCustomDirectory:(NSString *)path completion:(void (^)(int result))completion;
- (BOOL)removeCustomMountCopyAtPath:(NSString *)path;
- (BOOL)saveCustomMountPaths:(NSArray<NSString *> *)paths;
- (NSDictionary *)lowPowerScheduleConfiguration;
- (NSDictionary *)lowPowerScheduleStatus;
- (BOOL)saveLowPowerScheduleEnabled:(BOOL)enabled startMinute:(NSInteger)startMinute
                         endMinute:(NSInteger)endMinute error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
