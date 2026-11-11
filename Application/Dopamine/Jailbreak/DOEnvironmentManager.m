//
//  EnvironmentManager.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "DOEnvironmentManager.h"
#import "UIImage+JPEG2000.h"
#import "../../../BaseBin/roothidehooks/src/RCLowPowerSchedule.h"

#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <mach-o/dyld.h>
#import <libgrabkernel2/libgrabkernel2.h>
#import <libjailbreak/info.h>
#import <libjailbreak/codesign.h>
#import <libjailbreak/util.h>
#import <libjailbreak/display.h>
#import <libjailbreak/machine_info.h>
#import <libjailbreak/carboncopy.h>

#import <IOKit/IOKitLib.h>
#import "DOUIManager.h"
#import "DOExploitManager.h"
#import "DOPreferenceManager.h"
#import "NSData+Hex.h"
#import <LocalAuthentication/LocalAuthentication.h>
#include <notify.h>
#include <errno.h>

int reboot3(uint64_t flags, ...);
CFPropertyListRef MGCopyAnswer(CFStringRef);
extern char **environ;

@interface DOEnvironmentManager ()
@property(nonatomic) BOOL customMountTaskRunning;
@end

@implementation DOEnvironmentManager

+ (instancetype)sharedManager
{
    static DOEnvironmentManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DOEnvironmentManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bootstrapNeedsMigration = NO;
        _bootstrapper = [[DOBootstrapper alloc] init];
        if ([self isJailbroken]) {
            gSystemInfo.jailbreakInfo.rootPath = strdup(jbclient_get_jbroot() ?: "");
        }
        else if ([self isInstalledThroughTrollStore]) {
            [self locateJailbreakRoot];
        }
    }
    return self;
}

- (NSString *)nightlyHash
{
#ifdef NIGHTLY
    return [NSString stringWithUTF8String:COMMIT_HASH];
#else
    return nil;
#endif
}

- (NSString *)appVersion
{
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

- (NSString *)appVersionDisplayString
{
    NSString *nightlyHash = [self nightlyHash];
    if (nightlyHash) {
        return [NSString stringWithFormat:@"%@~%@", self.appVersion, [nightlyHash substringToIndex:6]];
    }
    else {
        return [self appVersion];
    }
}

- (NSString *)privatePrebootPath
{
    return @"/private/preboot";
}

- (NSString *)activePrebootPath
{
    NSString *bootManifestString = [NSString stringWithUTF8String:boot_manifest_hash()];
    return [[self privatePrebootPath] stringByAppendingPathComponent:bootManifestString];
}

/*
- (void)locateJailbreakRoot
{
    if (!gSystemInfo.jailbreakInfo.rootPath) {
        NSString *activePrebootPath = [self activePrebootPath];

        NSString *randomizedJailbreakPath;

        // First attempt at finding jailbreak root, look for Dopamine 2.x path
        for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
            if (subItem.length == 15 && [subItem hasPrefix:@"dopamine-"]) {
                randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:subItem];
                break;
            }
        }

        if (!randomizedJailbreakPath) {
            // Second attempt at finding jailbreak root, look for Dopamine 1.x path, but as other jailbreaks use it too, make sure it is Dopamine
            // Some other jailbreaks also commit the sin of creating .installed_dopamine, for these we try to filter them out by checking for their installed_ file
            // If we find this and are sure it's from Dopamine 1.x, rename it so all Dopamine 2.x users will have the same path
            for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
                if (subItem.length == 9 && [subItem hasPrefix:@"jb-"]) {
                    NSString *candidateLegacyPath = [activePrebootPath stringByAppendingPathComponent:subItem];

                    BOOL installedDopamine = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.installed_dopamine"]];

                    if (installedDopamine) {
                        // Hopefully all other jailbreaks that use jb-<UUID>?
                        // These checks exist because of dumb users (and jailbreak developers) creating .installed_dopamine on jailbreaks that are NOT dopamine...
                        BOOL installedNekoJB = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.installed_nekojb"]];
                        BOOL installedDefinitelyNotAGoodName = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.xia0o0o0o_jb_installed"]];
                        BOOL installedPalera1n = [[NSFileManager defaultManager] fileExistsAtPath:[candidateLegacyPath stringByAppendingPathComponent:@"procursus/.palecursus_strapped"]];
                        if (installedNekoJB || installedPalera1n || installedDefinitelyNotAGoodName) {
                            continue;
                        }

                        randomizedJailbreakPath = candidateLegacyPath;
                        _bootstrapNeedsMigration = YES;
                        break;
                    }
                }
            }
        }

        if (randomizedJailbreakPath) {
            NSString *jailbreakRootPath = [randomizedJailbreakPath stringByAppendingPathComponent:@"procursus"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:jailbreakRootPath]) {
                // This attribute serves as the primary source of what the root path is
                // Anything else in the jailbreak will get it from here
                gSystemInfo.jailbreakInfo.rootPath = strdup(jailbreakRootPath.fileSystemRepresentation);
            }
        }
    }
}

- (NSError *)ensureJailbreakRootExists
{
    NSError *error = nil;

    [self locateJailbreakRoot];

    // DOPACLEAN logic to move a corrupted dopamine directory to a different path to at least make jailbreaking work again
    // if (gSystemInfo.jailbreakInfo.rootPath) {
    //     NSString *randomizedJailbreakPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath].stringByDeletingLastPathComponent;
    //     NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    //     NSUInteger stringLen = 6;
    //     NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
    //     for (NSUInteger i = 0; i < stringLen; i++) {
    //         NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
    //         unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
    //         [randomString appendFormat:@"%C", randomCharacter];
    //     }

    //     NSString *activePrebootPath = [self activePrebootPath];
    //     NSString *orphanedName = [NSString stringWithFormat:@"orphaned-%@", randomString];
    //     NSString *orphanedPath = [activePrebootPath stringByAppendingPathComponent:orphanedName];
    //     [[NSFileManager defaultManager] moveItemAtPath:randomizedJailbreakPath toPath:orphanedPath error:nil];
    // }

    // return [NSError errorWithDomain:@"Cleaned" code:1 userInfo:nil];

    if (!gSystemInfo.jailbreakInfo.rootPath || _bootstrapNeedsMigration) {
        [_bootstrapper ensurePrivatePrebootIsWritable];

        NSString *activePrebootPath = [self activePrebootPath];

        NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        NSUInteger stringLen = 6;
        NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
        for (NSUInteger i = 0; i < stringLen; i++) {
            NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
            unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
            [randomString appendFormat:@"%C", randomCharacter];
        }

        NSString *randomJailbreakFolderName = [NSString stringWithFormat:@"dopamine-%@", randomString];
        NSString *randomizedJailbreakPath = [activePrebootPath stringByAppendingPathComponent:randomJailbreakFolderName];
        NSString *jailbreakRootPath = [randomizedJailbreakPath stringByAppendingPathComponent:@"procursus"];

        if (_bootstrapNeedsMigration) {
            NSString *oldRandomizedJailbreakPath = [[NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath] stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] moveItemAtPath:oldRandomizedJailbreakPath toPath:randomizedJailbreakPath error:&error];
        }
        else {
            if (![[NSFileManager defaultManager] fileExistsAtPath:jailbreakRootPath]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:jailbreakRootPath withIntermediateDirectories:YES attributes:nil error:&error];
            }
        }

        if (!error) {
            gSystemInfo.jailbreakInfo.rootPath = strdup(jailbreakRootPath.UTF8String);
        }
    }

    return error;
}
*/

- (BOOL)isArm64e
{
    cpu_subtype_t cpusubtype = 0;
    size_t len = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &len, NULL, 0) == -1) return NO;
    return (cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E;
}

- (NSString *)versionSupportString
{
    return [self isArm64e] ? @"iOS 16 (arm64e, PPL)" : @"iOS 16 (arm64)";
}

- (BOOL)isInstalledThroughTrollStore
{
    static BOOL trollstoreInstallation = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* trollStoreMarkerPath = [[[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"_TrollStore"];
        trollstoreInstallation = [[NSFileManager defaultManager] fileExistsAtPath:trollStoreMarkerPath];
    });
    return trollstoreInstallation;
}

- (void)updateJailbreakState
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *jbVersionC = NULL;
        _isJailbroken = jbclient_dopamine_is_jailbroken(&jbVersionC);
        if (jbVersionC) {
            _jailbrokenVersion = [NSString stringWithUTF8String:jbVersionC];
            free(jbVersionC);
        }
    });
}

- (BOOL)isJailbroken
{
/************** roothide specific ***********/
    if(!jbclient_roothide_jailbroken())
        return NO;
/************** roothide specific ********/

    [self updateJailbreakState];
    return _isJailbroken;
}

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version
{
    _isJailbroken = jailbroken;
    if (_isJailbroken) _jailbrokenVersion = version;
}

- (BOOL)isJailbrokenWithOtherJailbreak
{
    if (![self isJailbroken]) {
        uint32_t csFlags = 0;
        csops(getpid(), CS_OPS_STATUS, &csFlags, sizeof(csFlags));

        // Palera1n
        if (csFlags & CS_PLATFORM_BINARY) return YES;

        // Older Dopamine build
        if (!access("/usr/lib/systemhook.dylib", F_OK)) return YES;
    }
    return NO;
}

- (NSString *)jailbrokenVersion
{
    [self updateJailbreakState];
    if (!_isJailbroken) return nil;
    return _jailbrokenVersion;
}

- (NSString *)jailbrokenVersionRootHide
{
    NSString *versionFile = JBROOT_PATH(@"/basebin/.version-roothide");
    if(!versionFile) {
        return nil;
    }
    return [NSString stringWithContentsOfFile:versionFile encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)systemVersion
{
    return (__bridge NSString *)MGCopyAnswer((__bridge CFStringRef)@"ProductVersion");
}

- (BOOL)isBootstrapped
{
    return (BOOL)jbinfo(rootPath);
}

- (void)runUnsandboxed:(void (^)(void))unsandboxBlock
{
    if ([self isInstalledThroughTrollStore]) {
        unsandboxBlock();
    }
    else if ([self isJailbroken]) {
        uint64_t labelBackup = 0;
        jbclient_root_set_mac_label(1, -1, &labelBackup);
        unsandboxBlock();
        jbclient_root_set_mac_label(1, labelBackup, NULL);
    }
    else {
        // Hope that we are already unsandboxed
        unsandboxBlock();
    }
}

- (void)runAsRoot:(void (^)(void))rootBlock
{
    uint32_t orgUser = geteuid();
    uint32_t orgGroup = getegid();

    if (orgUser == 0 && orgGroup == 0) {
        rootBlock();
        return;
    }

    if (self.isJailbroken) {
        if (jbclient_dopamine_get_root() == 0) {
            rootBlock();
            jbclient_dopamine_drop_root();
        }
    }
}

- (int)spawnJbctlAsRootWithArgs:(NSArray *)args
{
    bool needsLegacySolution = false;
    if (self.jailbrokenVersion) {
        needsLegacySolution = (strcmp(self.jailbrokenVersion.UTF8String, "3.0.5") < 0);
    }

    int waitPipe[2] = {-1, -1};
    if (!needsLegacySolution && pipe(waitPipe) != 0)
        return errno;

    char **argBuf = malloc((args.count + 4) * sizeof(char *));
    argBuf[0] = strdup(JBROOT_PATH("/basebin/jbctl"));
    int i = 1;
    for (NSString *arg in args) {
        argBuf[i++] = strdup(arg.UTF8String);
    }

    if (!needsLegacySolution) {
        argBuf[i++] = strdup("--waitfor");
        argBuf[i++] = strdup("3");
    }
    argBuf[i++] = NULL;

    posix_spawn_file_actions_t act = NULL;
	posix_spawn_file_actions_init(&act);
    posix_spawnattr_t attr = NULL;
    posix_spawnattr_init(&attr);

    if (!needsLegacySolution) {
        posix_spawn_file_actions_adddup2(&act, waitPipe[0], 3);
    }
    else {
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
    }

    __block int pid = 0;
    __block int r = -1;

    [self runAsRoot:^{
        [self runUnsandboxed:^{
            r = posix_spawn(&pid, argBuf[0], &act, &attr, (char *const *)argBuf, (char *const *)environ);
            if (needsLegacySolution && r == 0 && pid > 0) {
                // Legacy solution is a gamble, which is why it was removed and superseeded by --waitfor
                // But if jailbroken with <3.0.5, jbctl doesn't support --waitfor yet
                kill(pid, SIGCONT);
            }
        }];
        // --waitfor resumes jbctl after leaving the privileged scope.
    }];

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&act);
    for (int y = 0; y < i; y++) {
        free(argBuf[y]);
    }
    free(argBuf);

    if (!needsLegacySolution) {
        if (r == 0) {
            // We left the root/unsandbox block, now resume jbctl by writing to pipe
            char w = 'w';
            write(waitPipe[1], &w, sizeof(w));
        }

        close(waitPipe[0]);
        close(waitPipe[1]);
    }

    if (r != 0 || pid <= 0)
        return r != 0 ? r : -1;
    return cmd_wait_for_exit(pid);
}

- (int)runTrollStoreAction:(NSString *)action
{
    if (![self isInstalledThroughTrollStore]) return -1;

    uint32_t selfPathSize = PATH_MAX;
    char selfPath[selfPathSize];
    _NSGetExecutablePath(selfPath, &selfPathSize);
    return exec_cmd_root(selfPath, "trollstore", action.UTF8String, NULL);
}

- (int)respring
{
    if (!self.isJailbroken) return EPERM;
    return [self spawnJbctlAsRootWithArgs:@[@"respring"]];
}

- (int)rebootUserspace
{
    if (!self.isJailbroken) return EPERM;
    return [self spawnJbctlAsRootWithArgs:@[@"reboot_userspace"]];
}

- (void)rebuildIconCache
{
    [self spawnJbctlAsRootWithArgs:@[@"rebuild_icon_cache"]];
}

- (void)refreshJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
        }];
    }];
}

- (void)unregisterJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSArray *jailbreakApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:JBROOT_PATH(@"/Applications") error:nil];
            if (jailbreakApps.count) {
                for (NSString *jailbreakApp in jailbreakApps) {
                    NSString *jailbreakAppPath = [JBROOT_PATH(@"/Applications") stringByAppendingPathComponent:jailbreakApp];
                    exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-u", jailbreakAppPath.fileSystemRepresentation, NULL);
                }
            }
        }];
    }];
}

- (int)reboot
{
    __block int result = -1;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            result = reboot3(0x8000000000000000, 0);
        }];
    }];
    return result;
}

- (void)changeMobilePassword:(NSString *)newPassword
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSString *dashCommand = [NSString stringWithFormat:@"printf \"%%s\\n\" \"%@\" | %@ usermod 501 -h 0", newPassword, JBROOT_PATH(@"/usr/sbin/pw")];
            exec_cmd(JBROOT_PATH("/usr/bin/dash"), "-c", dashCommand.UTF8String, NULL);
        }];
    }];
}

- (NSError*)updateEnvironment
{
    NSString *newBasebinTarPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin.tar"];
    int result = jbclient_platform_stage_jailbreak_update(newBasebinTarPath.fileSystemRepresentation);
    if (result == 0) {
        [self rebootUserspace];
        return nil;
    }
    return [NSError errorWithDomain:@"Dopamine" code:result userInfo:nil];
}

- (void)updateJailbreakFromTIPA:(NSString *)tipaPath
{
    [self spawnJbctlAsRootWithArgs:@[@"update", @"tipa", tipaPath]];
}

- (BOOL)isTweakInjectionEnabled
{
    return ![[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/basebin/.safe_mode")];
}

- (void)setTweakInjectionEnabled:(BOOL)enabled
{
    NSString *safeModePath = JBROOT_PATH(@"/basebin/.safe_mode");
    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                if (enabled) {
                    [[NSFileManager defaultManager] removeItemAtPath:safeModePath error:nil];
                }
                else {
                    [[NSData data] writeToFile:safeModePath atomically:YES];
                }
/*************************** roothide specific *******************/
                setBasebinDependency(enabled);
/*************************** roothide specific *******************/
            }];
        }];
    }
}

- (BOOL)isIDownloadEnabled
{
    __block BOOL isEnabled = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSDictionary *disabledDict = [NSDictionary dictionaryWithContentsOfFile:@"/var/db/com.apple.xpc.launchd/disabled.plist"];
            NSNumber *idownloaddDisabledNum = disabledDict[@"com.opa334.Dopamine.idownloadd"];
            if (idownloaddDisabledNum) {
                isEnabled = ![idownloaddDisabledNum boolValue];
            }
            else {
                isEnabled = NO;
            }
        }];
    }];
    return isEnabled;
}

- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox
{
    void (^updateBlock)(void) = ^{
        if (enabled) {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "enable", "system/com.opa334.Dopamine.idownloadd", NULL);
        }
        else {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "disable", "system/com.opa334.Dopamine.idownloadd", NULL);
        }
    };

    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }
}

- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox
{
    if (loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }

    void (^updateBlock)(void) = ^{
        if (loaded) {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "load", JBROOT_PATH("/basebin/LaunchDaemons/com.opa334.Dopamine.idownloadd.plist"), NULL);
        }
        else {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "unload", JBROOT_PATH("/basebin/LaunchDaemons/com.opa334.Dopamine.idownloadd.plist"), NULL);
        }
    };

    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }

    if (!loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }
}

/*
- (BOOL)isFakelibMounted
{
    struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

- (int)setFakelibMounted:(BOOL)mounted
{
    int r = 0;
    if (mounted != [self isFakelibMounted]) {
        NSString *arg = mounted ? @"mount" : @"unmount";
        r = [self spawnJbctlAsRootWithArgs:@[@"internal", @"fakelib", arg]];
    }
    return r;
}

- (int)setPrivatePrebootProtected:(BOOL)protected
{
    NSString *arg = protected ? @"activate" : @"deactivate";
    return [self spawnJbctlAsRootWithArgs:@[@"internal", @"protection", arg]];
}

- (BOOL)isJailbreakHidden
{
    return ![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

- (void)setJailbreakHidden:(BOOL)hidden
{
    if (hidden && ![self isJailbroken] && geteuid() != 0) {
        [self runTrollStoreAction:@"hide-jailbreak"];
        return;
    }

    void (^actionBlock)(void) = ^{
        BOOL alreadyHidden = [self isJailbreakHidden];
        if (hidden != alreadyHidden) {
            if (hidden) {
                if ([self isJailbroken]) {
                    [self unregisterJailbreakApps];
                    [self setPrivatePrebootProtected:NO];
                    [self setFakelibMounted:NO];
                    jbclient_platform_set_systemwide_domain_enabled(false);
                }
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
            }
            else {
                [[NSFileManager defaultManager] createSymbolicLinkAtPath:@"/var/jb" withDestinationPath:JBROOT_PATH(@"/") error:nil];
                if ([self isJailbroken]) {
                    jbclient_platform_set_systemwide_domain_enabled(true);
                    [self setFakelibMounted:YES];
                    [self setPrivatePrebootProtected:YES];
                    [self refreshJailbreakApps];
                }
            }
        }
    };

    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:actionBlock];
        }];
    }
    else {
        actionBlock();
    }
}
*/

- (NSString *)accessibleKernelPath
{
    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *kernelcachePath = [[self activePrebootPath] stringByAppendingPathComponent:@"System/Library/Caches/com.apple.kernelcaches/kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            return kernelcachePath;
        }
        return @"/System/Library/Caches/com.apple.kernelcaches/kernelcache";
    }
    else {
        NSString *kernelInApp = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelInApp]) {
            return kernelInApp;
        }

        [[DOUIManager sharedInstance] sendLog:@"Downloading Kernel" debug:NO];
        NSString *kernelcachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/kernelcache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            if (grab_images([NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]) == false) return nil;
        }
        return kernelcachePath;
    }
}

- (BOOL)isPACBypassRequired
{
    return NO;
}

- (BOOL)isPPLBypassRequired
{
    return [self isArm64e];
}

- (BOOL)isSupported
{
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 16) return NO;

    DOExploitManager *exploitManager = [DOExploitManager sharedManager];
    if ([exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL].count) {
        if (![self isPACBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC].count) {
            if (![self isPPLBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL].count) {
                return true;
            }
        }
    }

    return false;
}

- (BOOL)deviceSupportsFaceID
{
    if (![LAContext class]) return NO;

    LAContext *myContext = [[LAContext alloc] init];
    NSError *authError = nil;
    if (![myContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        NSLog(@"%@", [authError localizedDescription]);
        return NO;
    }

    return myContext.biometryType == LABiometryTypeFaceID;
}

- (BOOL)deviceSupportsLandscapeBootLogo
{
    struct utsname u;
    uname(&u);
    const char *ipadString = "iPad";

    bool isPad = strncmp(u.machine, ipadString, strlen(ipadString)) == 0;
    return isPad && [self deviceSupportsFaceID];
}

- (NSError *)prepareBootstrap
{
    __block NSError *errOut;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [_bootstrapper prepareBootstrapWithCompletion:^(NSError *error) {
        errOut = error;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return errOut;
}

- (NSError *)finalizeBootstrap
{
    return [_bootstrapper finalizeBootstrap];
}

- (NSError *)deleteBootstrap
{
    if (![self isJailbroken] && getuid() != 0) {
        int r = [self runTrollStoreAction:@"delete-bootstrap"];
        if (r != 0) {
            // TODO: maybe handle error
        }
        return nil;
    }
    else if ([self isJailbroken]) {
        __block NSError *error;
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                error = [self->_bootstrapper deleteBootstrap];
            }];
        }];
        return error;
    }
    else {
        // Let's hope for the best
        return [_bootstrapper deleteBootstrap];
    }
}

- (NSError *)reinstallPackageManagers
{
    __block NSError *error;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            error = [self->_bootstrapper installPackageManagers];
        }];
    }];
    return error;
}

- (NSError *)updateBootLogo
{
    const char *bootLogoPath = JBROOT_PATH("/basebin/bootlogo.jp2");
    if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
        UIImage *bootLogoImage;

        if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
            bootLogoImage = [NSClassFromString(@"UIImage") imageWithContentsOfFile:[DOUIManager sharedInstance].bootlogoPath];
        }

        if (!bootLogoImage) {
            bootLogoImage = [[DOUIManager sharedInstance] renderBootLogo];
        }

        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
                [[bootLogoImage jp2DataWithCompressionQuality:0.9] writeToFile:[NSString stringWithUTF8String:bootLogoPath] atomically:NO];
            }];
        }];

        return nil;
    }
    else {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
            }];
        }];
        return nil;
    }
}

- (NSString *)customMountListPath
{
    return JBROOT_PATH(@"/mnt/newFakePath.plist");
}

- (NSArray<NSString *> *)customMountPaths
{
    __block NSArray<NSString *> *paths = @[];
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSDictionary *configuration =
                [NSDictionary dictionaryWithContentsOfFile:[self customMountListPath]];
            id storedPaths = configuration[@"path"];
            if ([storedPaths isKindOfClass:NSArray.class])
                paths = [storedPaths copy];
        }];
    }];
    return paths;
}

- (BOOL)saveCustomMountPaths:(NSArray<NSString *> *)paths
{
    if (![paths isKindOfClass:NSArray.class]) return NO;
    NSString *mountRootPath = JBROOT_PATH(@"/mnt");
    for (id value in paths) {
        if (![value isKindOfClass:NSString.class]) return NO;
        NSString *path = value;
        if (![path hasPrefix:@"/"] || ![path isEqualToString:path.stringByStandardizingPath] ||
            [path isEqualToString:@"/"] || [path isEqualToString:@"/System"] ||
            [path isEqualToString:@"/private"] || [path isEqualToString:@"/var"] ||
            [path isEqualToString:@"/Applications"] || [path isEqualToString:@"/Library"] ||
            [path isEqualToString:@"/private/preboot"] || [path hasPrefix:@"/private/preboot/"] ||
            [path isEqualToString:@"/usr"] || [path hasPrefix:@"/usr/"] ||
            [path isEqualToString:mountRootPath] ||
            [path hasPrefix:[mountRootPath stringByAppendingString:@"/"]])
            return NO;
    }
    __block BOOL saved = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSString *mountRoot = JBROOT_PATH(@"/mnt");
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:mountRoot
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&error]) return;
            NSDictionary *configuration = @{@"path": paths};
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:configuration
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:&error];
            saved = data && [data writeToFile:[self customMountListPath]
                                      options:NSDataWritingAtomic
                                        error:&error];
        }];
    }];
    return saved;
}

- (int)mountCustomDirectory:(NSString *)path
{
    if (!self.isJailbroken || ![path isKindOfClass:NSString.class]) return -1;
    __block int result = -1;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            result = exec_cmd(JBROOT_PATH("/basebin/jbctl"), "internal", "mount",
                              path.fileSystemRepresentation, NULL);
        }];
    }];
    return result;
}

- (void)runCustomMountCommand:(NSString *)command path:(NSString *)path
                  completion:(void (^)(int result))completion
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self runCustomMountCommand:command path:path completion:completion];
        });
        return;
    }
    if (!self.isJailbroken || ![path isKindOfClass:NSString.class] ||
        self.customMountTaskRunning) {
        int result = self.customMountTaskRunning ? EBUSY : EINVAL;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        return;
    }
    self.customMountTaskRunning = YES;
    __block int spawnResult = -1;
    __block pid_t child = 0;
    // Only spawn inside the existing privilege scope. The child owns the copy
    // and mount; its wait happens after this process has restored its identity.
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            spawnResult = exec_cmd_nowait(&child, JBROOT_PATH("/basebin/jbctl"),
                                         "internal", command.UTF8String,
                                         path.fileSystemRepresentation, NULL);
        }];
    }];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int result = spawnResult;
        if (result == 0 && child > 0) {
            int status = 0;
            pid_t waited;
            do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
            result = waited == child ? status : -1;
        } else if (result == 0) {
            result = -1;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.customMountTaskRunning = NO;
            completion(result);
        });
    });
}

- (void)mountCustomDirectory:(NSString *)path completion:(void (^)(int result))completion
{
    [self runCustomMountCommand:@"mount" path:path completion:completion];
}

- (void)unmountCustomDirectory:(NSString *)path completion:(void (^)(int result))completion
{
    [self runCustomMountCommand:@"unmount" path:path completion:completion];
}

- (BOOL)removeCustomMountCopyAtPath:(NSString *)path
{
    if (![path isKindOfClass:NSString.class] ||
        ![path hasPrefix:@"/"] ||
        ![path isEqualToString:path.stringByStandardizingPath] ||
        [path isEqualToString:@"/"]) return NO;

    NSString *mountRoot = JBROOT_PATH(@"/mnt");
    NSString *copyPath = [mountRoot stringByAppendingString:path];
    if (![copyPath hasPrefix:[mountRoot stringByAppendingString:@"/"]]) return NO;

    __block BOOL removed = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSFileManager *manager = [NSFileManager defaultManager];
            if (![manager fileExistsAtPath:copyPath]) {
                removed = YES;
                return;
            }
            NSError *error = nil;
            removed = [manager removeItemAtPath:copyPath error:&error];
        }];
    }];
    return removed;
}

// 根据注入配置是否存在返回模式简称，供系统版本后的括号显示。
- (NSString *)injectionModeDescription
{
    if (!self.isJailbroken) return DOLocalizedString(@"Injection_Mode_Waiting");
    BOOL whitelist = access(JBROOT_PATH("/var/mobile/Library/RootHide/cn.zqbb.inject.plist"), F_OK) == 0;
    return whitelist ? @"Whitelist" : @"Blacklist";
}

// 读取当前 Sileo 的 URL scheme，兼容 RootHide 重写。
- (NSString *)sileoURLScheme {
    if (!self.isJailbroken) {
        return @"sileo";
    }

    NSString *path = JBROOT_PATH(@"/Applications/Sileo.app/Info.plist");
    NSDictionary *info = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    id urlTypes = info[@"CFBundleURLTypes"];
    if (![urlTypes isKindOfClass:NSArray.class]) {
        return @"sileo";
    }

    for (id urlType in urlTypes) {
        if (![urlType isKindOfClass:NSDictionary.class]) {
            continue;
        }
        id schemes = urlType[@"CFBundleURLSchemes"];
        if (![schemes isKindOfClass:NSArray.class]) {
            continue;
        }
        for (id scheme in schemes) {
            if (![scheme isKindOfClass:NSString.class] || [scheme length] == 0) {
                continue;
            }
            NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:@"://package"]];
            if ([url.scheme isEqualToString:scheme] && [url.host isEqualToString:@"package"]) {
                return scheme;
            }
        }
    }
    return @"sileo";
}

- (NSDictionary *)lowPowerScheduleConfiguration
{
    __block NSDictionary *configuration;
    [self runUnsandboxed:^{
        configuration = rcLowPowerReadDictionary(
            rcLowPowerConfigurationPath(JBROOT_PATH(@"/")));
    }];
    return configuration ?: rcLowPowerDefaultConfiguration();
}

- (NSDictionary *)lowPowerScheduleStatus
{
    __block NSDictionary *status;
    [self runUnsandboxed:^{
        status = rcLowPowerReadDictionary(
            rcLowPowerStatusPath(JBROOT_PATH(@"/")));
    }];
    return status ?: @{};
}

- (BOOL)saveLowPowerScheduleEnabled:(BOOL)enabled
                        startMinute:(NSInteger)startMinute
                          endMinute:(NSInteger)endMinute
                              error:(NSError **)error
{
    NSDictionary *configuration = @{
        @"Version": @1,
        @"Enabled": @(enabled),
        @"StartMinute": @(startMinute),
        @"EndMinute": @(endMinute),
        @"Revision": NSUUID.UUID.UUIDString
    };
    if (!self.isJailbroken || !rcLowPowerConfigurationValid(configuration)) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:self.isJailbroken ? EINVAL : EPERM
                                     userInfo:nil];
        }
        return NO;
    }

    __block BOOL success = NO;
    __block NSError *writeError = nil;
    [self runUnsandboxed:^{
        success = rcLowPowerWriteDictionary(
            configuration,
            rcLowPowerConfigurationPath(JBROOT_PATH(@"/")),
            &writeError);
    }];
    if (success) {
        notify_post(RC_LOW_POWER_CHANGED);
    } else if (error) {
        *error = writeError;
    }
    return success;
}

@end
