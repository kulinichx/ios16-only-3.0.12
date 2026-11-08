#import "internal.h"
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <string.h>
#import <limits.h>
#import <errno.h>
SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

static int mount_unsandboxed(const char *type, const char *dir, int flags, void *data)
{
	uint64_t credBackup = 0;
	int result = jbclient_root_steal_ucred(0, &credBackup);
	if (result != 0) return result;
	result = mount(type, dir, flags, data);
	jbclient_root_steal_ucred(credBackup, NULL);
	return result;
}

static int unmount_unsandboxed(const char *dir, int flags)
{
	uint64_t credBackup = 0;
	int result = jbclient_root_steal_ucred(0, &credBackup);
	if (result != 0) return result;
	result = unmount(dir, flags);
	jbclient_root_steal_ucred(credBackup, NULL);
	return result;
}

static bool custom_mount_path_is_valid(const char *rawPath)
{
	if (!rawPath || rawPath[0] != '/' || strnlen(rawPath, PATH_MAX) >= PATH_MAX) return false;
	NSString *path = [NSString stringWithUTF8String:rawPath];
	if (!path || ![path isEqualToString:path.stringByStandardizingPath] ||
		[path isEqualToString:@"/"] ||
		[path isEqualToString:@"/System"] ||
		[path isEqualToString:@"/private"] ||
		[path isEqualToString:@"/var"] ||
		[path isEqualToString:@"/Applications"] ||
		[path isEqualToString:@"/Library"] ||
		[path isEqualToString:@"/private/preboot"] ||
		[path hasPrefix:@"/private/preboot/"] ||
		[path isEqualToString:@"/usr"] ||
		[path hasPrefix:@"/usr/"] ||
		[path isEqualToString:JBROOT_PATH(@"/mnt")] ||
		[path hasPrefix:[JBROOT_PATH(@"/mnt") stringByAppendingString:@"/"]])
		return false;

	struct stat info;
	if (lstat(rawPath, &info) != 0 || !S_ISDIR(info.st_mode) || S_ISLNK(info.st_mode)) return false;
	return true;
}

static bool fake_path_is_mounted(const char *path)
{
	struct statfs fs;
	return statfs(path, &fs) == 0 && strcmp(fs.f_mntonname, path) == 0;
}

static int prepare_mount_copy(const char *rawPath)
{
	NSString *path = [NSString stringWithUTF8String:rawPath];
	NSString *mountPath = [JBROOT_PATH(@"/mnt") stringByAppendingString:path];
	NSFileManager *manager = [NSFileManager defaultManager];
	BOOL isDirectory = NO;
	if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return -1;

	NSString *parent = [mountPath stringByDeletingLastPathComponent];
	NSError *error = nil;
	if (![manager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&error])
		return -1;

	if ([manager fileExistsAtPath:mountPath isDirectory:&isDirectory]) {
		if (!isDirectory) return EEXIST;
		NSArray *contents = [manager contentsOfDirectoryAtPath:mountPath error:&error];
		if (!contents) return EIO;
		if (contents.count > 0) return 0;
		if (![manager removeItemAtPath:mountPath error:&error]) return EIO;
	}

	NSString *temporaryPath = [mountPath stringByAppendingString:@"_tmp"];
	if ([manager fileExistsAtPath:temporaryPath] &&
		![manager removeItemAtPath:temporaryPath error:&error]) return EIO;
	if (![manager copyItemAtPath:path toPath:temporaryPath error:&error]) return EIO;
	if (![manager moveItemAtPath:temporaryPath toPath:mountPath error:&error]) {
		[manager removeItemAtPath:temporaryPath error:nil];
		return EIO;
	}
	return 0;
}

static int fake_path_mount(bool mount, const char *path)
{
	if (!custom_mount_path_is_valid(path)) return EINVAL;
	if (mount == fake_path_is_mounted(path)) return 0;
	if (mount) {
		int result = prepare_mount_copy(path);
		if (result != 0) return result;
		NSString *source = [JBROOT_PATH(@"/mnt") stringByAppendingString:
			[NSString stringWithUTF8String:path]];
		return mount_unsandboxed("bindfs", path, MNT_RDONLY, (void *)source.fileSystemRepresentation);
	}
	return unmount_unsandboxed(path, MNT_FORCE);
}

int jbctl_handle_internal(const char *command, int argc, char* argv[])
{
	if (!strcmp(command, "launchd_stash_port")) {
		mach_port_t *selfInitPorts = NULL;
		mach_msg_type_number_t selfInitPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
			printf("ERROR: Failed port lookup on self\n");
			return -1;
		}
		if (selfInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on self\n");
			return -1;
		}
		if (selfInitPorts[2] == MACH_PORT_NULL) {
			printf("ERROR: Port to stash not set\n");
			return -1;
		}

		printf("Port to stash: %u\n", selfInitPorts[2]);

		mach_port_t launchdTaskPort;
		if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
			printf("task_for_pid on launchd failed\n");
			return -1;
		}
		mach_port_t *launchdInitPorts = NULL;
		mach_msg_type_number_t launchdInitPortsCount = 0;
		if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
			printf("mach_ports_lookup on launchd failed\n");
			return -1;
		}
		if (launchdInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on launchd\n");
			return -1;
		}
		launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
		if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
			printf("ERROR: Failed stashing port into launchd\n");
			return -1;
		}
		mach_port_deallocate(mach_task_self(), launchdTaskPort);
		return 0;
	}
/*
	else if (!strcmp(command, "protection")) {
		bool toSet = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "activate")) {
				toSet = true;
			}
			else if (!strcmp(argv[1], "deactivate")) {
				toSet = false;
			}
			else {
				return -1;
			}

			return protection_set_active(toSet);
		}
		return -1;
	}
	else if (!strcmp(command, "fakelib")) {
		bool toMount = false;
		if (argc > 1) {
			if (!strcmp(argv[1], "mount")) {
				toMount = true;
			}
			else if (!strcmp(argv[1], "unmount")) {
				toMount = false;
			}
			else {
				return -1;
			}

			return fakelib_set_mounted(toMount);
		}
		return -1;
	}
*/
	else if (!strcmp(command, "startup")) {
//		protection_set_active(true);

JBLogDebug("jbctl startup: checking userspace panic ...");

		char *panicMessage = NULL;
		if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
			NSString *printMessage = [NSString stringWithFormat:@"Dopamine has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Dopamine app.\n\nPanic message: \n%s", panicMessage];
			CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), (__bridge CFStringRef)printMessage, NULL, NULL, NULL, NULL);
			free(panicMessage);
		}

/************************* roothide specific ***************************/
//only bootstrap after launchdhook and systemhook available
JBLogDebug("jbctl startup: bootstrapping launch daemons ...");
exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "bootstrap", "system", "/Library/LaunchDaemons", NULL);

JBLogDebug("jbctl startup: refreshing jailbroken apps ...");

if(access(JBROOT_PATH("/.disable_auto_uicache"), F_OK) == 0) {
	return 0;
}
/************************* roothide specific ***************************/

		exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
	}
	else if (!strcmp(command, "mount") || !strcmp(command, "unmount")) {
		if (argc < 2 || !custom_mount_path_is_valid(argv[1])) return EINVAL;
		bool shouldMount = !strcmp(command, "mount");
		return fake_path_mount(shouldMount, argv[1]);
	}
	else if (!strcmp(command, "install_pkg")) {
		if (argc > 1) {
			extern char **environ;
			const char *dpkg = JBROOT_PATH("/usr/bin/dpkg");
			int r = execve(dpkg, (char *const *)(const char *[]){dpkg, "-i", argv[1], NULL}, environ);
			return r;
		}
		return -1;
	}
	return -1;
}
