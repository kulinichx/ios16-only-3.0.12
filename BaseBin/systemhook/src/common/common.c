#include "common.h"
#include "_zqbb.h"
#include <errno.h>
#include <limits.h>
#include "../roothider.h"
#include <xpc/xpc.h>
#include <xpc_private.h>
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sandbox.h>
#include <paths.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include "envbuf.h"
#include "private.h"
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/jbserver_domains.h>
#include <libjailbreak/util.h>
#include <libjailbreak/jbroot.h>
#include <libroothider/_configuration.h>
#include <libkern/OSCacheControl.h>

bool string_has_prefix(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

bool string_has_suffix(const char* str, const char* suffix)
{
	if (!str || !suffix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t suffix_len = strlen(suffix);

	if (str_len < suffix_len) {
		return false;
	}

	return !strcmp(str + str_len - suffix_len, suffix);
}

void string_enumerate_components(const char *string, const char *separator, void (^enumBlock)(const char *pathString, bool *stop))
{
	if (!string || !separator || !enumBlock) return;
	char *stringCopy = strdup(string);
	if (!stringCopy) return;
	char *state = NULL;
	char *curString = strtok_r(stringCopy, separator, &state);
	while (curString != NULL) {
		bool stop = false;
		enumBlock(curString, &stop);
		if (stop) break;
		curString = strtok_r(NULL, separator, &state);
	}
	free(stringCopy);
}

// Retain this invocation's value before releasing its independent snapshot.
// No shared cache or lock can be inherited across a fork or replaced by a peer.
static XPC_RETURNS_RETAINED xpc_object_t jbuserconfig_copy_value(const char *key)
{
	xpc_object_t config = zqbb_read_dictionary(JBROOT_PATH("/basebin/config.plist"));
	if (!config) return NULL;
	xpc_object_t value = xpc_dictionary_get_value(config, key);
	if (value) xpc_retain(value);
	xpc_release(config);
	return value;
}

static kSpawnConfig spawn_config_for_executable(const char* path, char *const argv[restrict])
{
	// Blacklist to ensure general system stability
	// I don't like this but for some processes it seems neccessary
	const char *processBlacklist[] = {
		"/System/Library/Frameworks/GSS.framework/Helpers/GSSCred",
		"/System/Library/PrivateFrameworks/DataAccess.framework/Support/dataaccessd",
		"/System/Library/PrivateFrameworks/IDSBlastDoorSupport.framework/XPCServices/IDSBlastDoorService.xpc/IDSBlastDoorService",
		"/System/Library/PrivateFrameworks/MessagesBlastDoorSupport.framework/XPCServices/MessagesBlastDoorService.xpc/MessagesBlastDoorService",
	};
	size_t blacklistCount = sizeof(processBlacklist) / sizeof(processBlacklist[0]);
	for (size_t i = 0; i < blacklistCount; i++)
	{
		if (!strcmp(processBlacklist[i], path)) return 0;
	}

	xpc_object_t userBlacklist = jbuserconfig_copy_value("ProcessBlacklist");
	if (userBlacklist && xpc_get_type(userBlacklist) == XPC_TYPE_ARRAY) {
		size_t userBlacklistCount = xpc_array_get_count(userBlacklist);
		for (size_t i = 0; i < userBlacklistCount; i++) {
			const char *blacklistedPath = xpc_array_get_string(userBlacklist, i);
			if (blacklistedPath && !strcmp(blacklistedPath, path)) {
				xpc_release(userBlacklist);
				return kSpawnConfigTrust;
			}
		}
	}
	if (userBlacklist) xpc_release(userBlacklist);

    // 白名单文件存在时，仅允许匹配的进程注入。
    const char *injectPath = JBROOT_PATH("/var/mobile/Library/RootHide/cn.zqbb.inject.plist");
    if (access(injectPath, F_OK) == 0) {
        const char *exec = strrchr(path, '/');
        if ((!exec || !zqbb_wantInject(exec + 1, injectPath)) && !zqbb_isWhiteList(path))
            return 0;
    }
	return (kSpawnConfigInject | kSpawnConfigTrust);
}

kSpawnConfig roothide_spawn_config_for_executable(const char* path, char *const argv[restrict])
{
	return spawn_config_for_executable(path, argv);
}

// 1. Ensure the binary about to be spawned and all of it's dependencies are trust cached
// 2. Insert "DYLD_INSERT_LIBRARIES=/usr/lib/systemhook.dylib" into all binaries spawned
// 3. Increase Jetsam limit to more sane value (Multipler defined as JETSAM_MULTIPLIER)

static int spawn_exec_hook_common(bool isExec,
						   const char *path,
						   char *const argv[restrict],
						   char *const envp[restrict],
		struct _posix_spawn_args_desc *desc,
								 int (*trust_binary)(const char *path),
								double jetsamMultiplier,
								 int (^orig)(pid_t *pid, char *const envp[restrict]))
{
	if (!path) {
		return orig(NULL, envp);
	}
	posix_spawnattr_t attr = NULL;
	if (desc) attr = desc->attrp;

	// Callers may reuse attr; keep the MB adjustment local to this spawn.
	int memlimitActiveOrig = -1, memlimitInactiveOrig = -1;

	kSpawnConfig spawnConfig = spawn_config_for_executable(path, argv);

	if (spawnConfig & kSpawnConfigTrust) {
		// Upload binary to trustcache if needed
		trust_binary(path);
	}

	const char *existingLibraryInserts = envbuf_getenv((const char **)envp, "DYLD_INSERT_LIBRARIES");
	__block bool systemHookAlreadyInserted = false;
	if (existingLibraryInserts) {
		string_enumerate_components(existingLibraryInserts, ":", ^(const char *existingLibraryInsert, bool *stop) {
			if (!strcmp(existingLibraryInsert, HOOK_DYLIB_PATH)) {
				systemHookAlreadyInserted = true;
			}
		});
	}

	int JBEnvAlreadyInsertedCount = (int)systemHookAlreadyInserted;

	// Check if we can find at least one reason to not insert jailbreak related environment variables
	// In this case we also need to remove pre existing environment variables if they are already set
	bool shouldInsertJBEnv = true;
	bool hasSafeModeVariable = false;
	do {
		if (!(spawnConfig & kSpawnConfigInject)) {
			shouldInsertJBEnv = false;
			break;
		}

		// Check if we can find a _SafeMode or _MSSafeMode variable
		// In this case we do not want to inject anything
		const char *safeModeValue = envbuf_getenv((const char **)envp, "_SafeMode");
		const char *msSafeModeValue = envbuf_getenv((const char **)envp, "_MSSafeMode");
		if (safeModeValue) {
			if (!strcmp(safeModeValue, "1")) {
				if(!allowInjectWithSafeMode(path)) shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}
		if (msSafeModeValue) {
			if (!strcmp(msSafeModeValue, "1")) {
				if(!allowInjectWithSafeMode(path)) shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}

		int proctype = 0;
		if (posix_spawnattr_getprocesstype_np(&attr, &proctype) == 0) {
			if (proctype == POSIX_SPAWN_PROC_TYPE_DRIVER) {
				// Do not inject hook into DriverKit drivers
				shouldInsertJBEnv = false;
				break;
			}
		}

		if (access(HOOK_DYLIB_PATH, F_OK) != 0) {
			// If the hook dylib doesn't exist, don't try to inject it (would crash the process)
			shouldInsertJBEnv = false;
			break;
		}
	} while (0);

	uint8_t *attrStruct = (uint8_t *)attr;
	if (attrStruct) {
		// 注入进程按配置增加内存额度，保留无限额设置。
		if (shouldInsertJBEnv) {
			if (jetsamMultiplier == 0 || !isfinite(jetsamMultiplier)) jetsamMultiplier = 3; // default value (3x)
			if (jetsamMultiplier > 1) {
                double configuredAddend = zqbb_getJetsamAddend(path) + round(jetsamMultiplier * 10);
                int jetsamAddend = configuredAddend >= INT_MAX ? INT_MAX : (int)configuredAddend;
				int memlimit_active = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE);
				if (memlimit_active != -1) {
					memlimitActiveOrig = memlimit_active;
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE) = (int)min((int64_t)INT_MAX, (int64_t)memlimit_active + jetsamAddend);
				}
				int memlimit_inactive = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE);
				if (memlimit_inactive != -1) {
					memlimitInactiveOrig = memlimit_inactive;
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE) = (int)min((int64_t)INT_MAX, (int64_t)memlimit_inactive + jetsamAddend);
				}
			}
		}
	}

	int r = -1;
	int spawnError = 0;

	pid_t childPid = -1;

	if ((shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 1) || (!shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 0 && !hasSafeModeVariable)) {
		// we're already good, just call orig
		r = orig(&childPid, envp);
		spawnError = errno;
	}
	else {
		// the state we want to be in is not the state we are in right now

		char **envc = envbuf_mutcopy((const char **)envp);

		if (shouldInsertJBEnv) {
			if (!systemHookAlreadyInserted) {
				char newLibraryInsert[strlen(HOOK_DYLIB_PATH) + (existingLibraryInserts ? (strlen(existingLibraryInserts) + 1) : 0) + 1];
				strcpy(newLibraryInsert, HOOK_DYLIB_PATH);
				if (existingLibraryInserts) {
					strcat(newLibraryInsert, ":");
					strcat(newLibraryInsert, existingLibraryInserts);
				}
				envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);
			}
		}
		else {
			if (systemHookAlreadyInserted && existingLibraryInserts) {
				if (!strcmp(existingLibraryInserts, HOOK_DYLIB_PATH)) {
					envbuf_unsetenv(&envc, "DYLD_INSERT_LIBRARIES");
				}
				else {
					char *newLibraryInsert = malloc(strlen(existingLibraryInserts)+1);
					newLibraryInsert[0] = '\0';

					__block bool first = true;
					string_enumerate_components(existingLibraryInserts, ":", ^(const char *existingLibraryInsert, bool *stop) {
						if (strcmp(existingLibraryInsert, HOOK_DYLIB_PATH) != 0) {
							if (first) {
								strcpy(newLibraryInsert, existingLibraryInsert);
								first = false;
							}
							else {
								strcat(newLibraryInsert, ":");
								strcat(newLibraryInsert, existingLibraryInsert);
							}
						}
					});
					envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);

					free(newLibraryInsert);
				}
			}
			envbuf_unsetenv(&envc, "_SafeMode");
			envbuf_unsetenv(&envc, "_MSSafeMode");
		}

		r = orig(&childPid, envc);
		spawnError = errno;

		envbuf_free(envc);
	}

	if (memlimitActiveOrig != -1) {
		*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE) = memlimitActiveOrig;
	}
	if (memlimitInactiveOrig != -1) {
		*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE) = memlimitInactiveOrig;
	}

	errno = spawnError;
	return r;
}

int posix_spawn_hook_shared(pid_t *restrict pid,
					   const char *restrict path,
			 struct _posix_spawn_args_desc *desc,
						  	    char *const argv[restrict],
					   			char *const envp[restrict],
					   				  void *orig,
					   				  int (*trust_binary)(const char *path),
					   				  int (*set_process_debugged)(uint64_t pid, bool fullyDebugged),
					   				 double jetsamMultiplier)
{
	int (*posix_spawn_orig)(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *, char *const[restrict], char *const[restrict]) = orig;

	int r = spawn_exec_hook_common(false, path, argv, envp, desc, trust_binary, jetsamMultiplier, ^int(pid_t *pidOut, char *const envp_patched[restrict]) {
		int rr = posix_spawn_orig(pid ?: pidOut, path, desc, argv, envp_patched);
		if (rr == 0 && pid && pidOut) {
			*pidOut = *pid;
		}
		return rr;
	});
	int spawnError = errno;

	if (r == 0 && pid && desc) {
		posix_spawnattr_t attr = desc->attrp;
		short flags = 0;
		if (posix_spawnattr_getflags(&attr, &flags) == 0) {
			if (flags & POSIX_SPAWN_START_SUSPENDED) {
				// If something spawns a process as suspended, ensure mapping invalid pages in it is possible
				// Normally it would only be possible after systemhook.dylib enables it
				// Fixes Frida issues
				set_process_debugged(*pid, false);
			}
		}
	}

	errno = spawnError;
	return r;
}

kern_return_t vm_allocate_nearby(vm_map_t target_task, vm_address_t from_area, vm_size_t from_area_size, vm_address_t *address, vm_size_t size, uint64_t limit)
{
	if (from_area != 0 && from_area_size > 0 && address) {
		// Make sure allocation is within limit for every single page in the area
		uint64_t realLimit = limit - (from_area_size / 2);

		for (uint64_t off = 0; off < realLimit; off += vm_page_size) {
			vm_address_t tmp = (from_area + from_area_size) + off;
			kern_return_t kr = vm_allocate(target_task, &tmp, size, VM_FLAGS_FIXED);
			if (kr == KERN_SUCCESS) {
				*address = tmp;
				return kr;
			}

			tmp = (from_area - size) - off;
			kr = vm_allocate(target_task, &tmp, size, VM_FLAGS_FIXED);
			if (kr == KERN_SUCCESS) {
				*address = tmp;
				return kr;
			}
		}
	}

	return KERN_NO_SPACE;
}

int execve_hook_shared(const char *path,
					   char *const argv[],
					   char *const envp[],
			 				 void *orig,
			 				 int (*trust_binary)(const char *path))
{
	int (*execve_orig)(const char *, char *const[], char *const[]) = orig;

	int r = spawn_exec_hook_common(true, path, argv, envp, NULL, trust_binary, 0, ^int(pid_t *pidOut, char *const envp_patched[restrict]){
		return execve_orig(path, argv, envp_patched);
	});

	return r;
}

__attribute__((noinline, naked)) volatile void *get_tpidrr0_el0(void)
{
	asm("MRS X0, TPIDRRO_EL0");
	asm("RET");
}
