#include <choma/Fat.h>
#include <choma/MachO.h>
#include <choma/Host.h>
#include <mach-o/dyld.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/signatures.h>

#include <sys/stat.h>
#include <sys/mount.h>
#import <Foundation/Foundation.h>

#include "libroothider.h"

#define DEBUG_LOG(...) //JBLogDebug(__VA_ARGS__)

MachO* fat_find_preferred_slice(Fat *fat)
{
	cpu_type_t cputype;
	cpu_subtype_t cpusubtype;
	if (host_get_cpu_information(&cputype, &cpusubtype) != 0) { return NULL; }
	
	MachO *candidateSlice = NULL;

	if (cpusubtype == CPU_SUBTYPE_ARM64E) {
		// New arm64e ABI
		candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2);
		if (!candidateSlice) {
			// Old arm64e ABI
			candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E);
			if (candidateSlice) {
				// If we found an old arm64e slice, make sure this is a library! If it's a binary, skip!!!
				// For binaries the system will fall back to the arm64 slice, which has the CDHash that we want to add
				if (macho_get_filetype(candidateSlice) == MH_EXECUTE) candidateSlice = NULL;
			}
		}
	}

	if (!candidateSlice) {
		// On iOS 15+ the kernels prefers ARM64_V8 to ARM64_ALL
		candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_V8);
		if (!candidateSlice) {
			candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_ALL);
		}
	}

	return candidateSlice;
}

NSString* resolveLoaderExecutablePaths(NSString *loadPath, NSString *loaderPath, NSString *mainExecutablePath, NSString* workingDir)
{
	NSString* result = nil;
	if ([loadPath hasPrefix:@"@loader_path/"] || [loadPath isEqualToString:@"@loader_path"]) {
		result = [loadPath stringByReplacingCharactersInRange:NSMakeRange(0,sizeof("@loader_path")-1) withString:loaderPath.stringByDeletingLastPathComponent];
	}
	else if ([loadPath hasPrefix:@"@executable_path/"] || [loadPath isEqualToString:@"@executable_path"]) {
		result = [loadPath stringByReplacingCharactersInRange:NSMakeRange(0,sizeof("@executable_path")-1) withString:mainExecutablePath.stringByDeletingLastPathComponent];
	}
	if (result && ![result hasPrefix:@"/"] && workingDir) {
		result = [workingDir stringByAppendingPathComponent:result];
	}
	return result;
};

NSString* resolveRpaths(NSString *subPath, NSString *mainExecutablePath, NSString* workingDir, NSArray* rpathStack)
{
@autoreleasepool {

	DEBUG_LOG("Resolving rpaths for %s, mainExecutable: %s, rpathStack: %s", subPath.fileSystemRepresentation, mainExecutablePath.fileSystemRepresentation, rpathStack.description.UTF8String);

	__block NSString *rpathResolvedPath = nil;

	for (NSString* loaderPath in rpathStack.reverseObjectEnumerator)
	{
		Fat *fat = fat_init_from_path(loaderPath.fileSystemRepresentation);
		if (fat) {
			MachO *macho = fat_find_preferred_slice(fat);
			if (macho) {
				macho_enumerate_rpaths(macho, ^(const char *rpathCStr, bool *stop) {
					NSString* possiblePath = [@(rpathCStr) stringByAppendingPathComponent:subPath];
					possiblePath = resolveLoaderExecutablePaths(possiblePath, loaderPath, mainExecutablePath, workingDir) ?: possiblePath;
					if(![possiblePath hasPrefix:@"/"]) { // dyld only supports relative path in rpath on macOS
						JBLogDebug("Skipping relative rpath: %s -> %s", subPath.fileSystemRepresentation, possiblePath.fileSystemRepresentation);
						return;
					}
					if (_dyld_shared_cache_contains_path(possiblePath.fileSystemRepresentation)
					 || [[NSFileManager defaultManager] fileExistsAtPath:possiblePath]) {
						rpathResolvedPath = possiblePath;
						*stop = true;
					}
				});
			}
			fat_free(fat);
		}

		if(rpathResolvedPath)
			break;
	}
	
	return rpathResolvedPath;

} //autoreleasepool
}

NSString *resolveLoadPath(NSString *loadPath, NSString *loaderPath, NSString *mainExecutablePath, NSString* workingDir, NSArray* rpathStack)
{
	if (!loadPath) return nil;

	if ([loadPath hasPrefix:@"@rpath/"]) {
		return resolveRpaths([loadPath substringFromIndex:(sizeof("@rpath/")-1)], mainExecutablePath, workingDir, rpathStack);
	}
	
	NSString *expandedPath = resolveLoaderExecutablePaths(loadPath, loaderPath, mainExecutablePath, workingDir);
	if (expandedPath) {
		return expandedPath;
	}

	if([loadPath hasPrefix:@"@"]) { // dyld does not support this path
		JBLogDebug("Skipping unresolvable loadPath: %s", loadPath.fileSystemRepresentation);
		return nil;
	}

	if(![loadPath hasPrefix:@"/"])
	{
		JBLogDebug("Resolving relative path: %s", loadPath.fileSystemRepresentation);

		//non-@ path is treated as an implicit @rpath first
		NSString* resolvedPath = resolveRpaths(loadPath, mainExecutablePath, workingDir, rpathStack);

		if(!resolvedPath && workingDir) {
			resolvedPath = [workingDir stringByAppendingPathComponent:loadPath];
		}

		return resolvedPath;
	}
	
	return loadPath; //absolute path
}

static void recurse_handler(NSString *loadPath, NSString *loaderPath, NSString *mainExecutablePath, NSString *workingDir, NSMutableArray* fileCaches, NSMutableArray* rpathStack, preferredArchInfo* preferredArch, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut, int *result)
{
@autoreleasepool {
	if (*result != 0) return;

	DEBUG_LOG("Recursing into loadPath: %s\n\tloader: %s\n\tmainExecutable: %s\nworkingDir: %s\n", loadPath.fileSystemRepresentation, loaderPath.fileSystemRepresentation, mainExecutablePath.fileSystemRepresentation, workingDir.fileSystemRepresentation);

	bool (^cdhashesContains)(cdhash_t) = ^bool(cdhash_t cdhash) {
		for (int i = 0; i < (*cdhashCountOut); i++) {
			if (!memcmp((*cdhashesOut)[i], cdhash, sizeof(cdhash_t))) {
				return true;
			}
		}
		return false;
	};
	void (^cdhashesAdd)(cdhash_t) = ^(cdhash_t cdhash) {
		if (*cdhashCountOut == UINT32_MAX) { *result = -1; return; }
		cdhash_t *expanded = realloc(*cdhashesOut, ((size_t)*cdhashCountOut + 1) * sizeof(cdhash_t));
		if (!expanded) { *result = -1; return; }
		*cdhashesOut = expanded;
		memcpy(expanded[(*cdhashCountOut)++], cdhash, sizeof(cdhash_t));
	};


	NSString *resolvedLoadPath = resolveLoadPath(loadPath, loaderPath, mainExecutablePath, workingDir, rpathStack);
	if(!resolvedLoadPath) {
		JBLogError("Failed to resolve dependency library for %s (loader: %s, mainExecutable: %s)", loadPath.fileSystemRepresentation, loaderPath.fileSystemRepresentation, mainExecutablePath.fileSystemRepresentation);
		return;
	}

	if(_dyld_shared_cache_contains_path(resolvedLoadPath.fileSystemRepresentation)) {
		DEBUG_LOG("Skipping dyld shared cached library: %s", resolvedLoadPath.fileSystemRepresentation);
		return;
	}

	char realfilepath[PATH_MAX] = {0};
	int fd = open(resolvedLoadPath.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		JBLogError("Failed to open binary at path: %s (loader: %s)", resolvedLoadPath.fileSystemRepresentation, loaderPath.fileSystemRepresentation);
		return;
	}
	if(fcntl(fd, F_GETPATH, realfilepath) != 0) {
		JBLogError("Failed to get file path for fd %d", fd);
		close(fd);
		return;
	}
	close(fd);

	if(string_has_prefix(realfilepath, "/private/preboot/Cryptexes/")) {
		JBLogDebug("Skipping Cryptexes file: %s", realfilepath);
		return;
	}
	
	if(isRemovableBundlePath(realfilepath) && !hasTrollstoreLiteMarker(realfilepath) && !hasJailFoolsMarker(realfilepath)) {
		// ignore adhoc signed apps(removable system apps or other stuffs) which is not installed via tslite
		JBLogDebug("ignoring addhoc signed app: %s\n", realfilepath);
		return;
	}
	
	struct statfs fs;
	int sfsret = statfs(realfilepath, &fs);
	if(sfsret == 0) {
		if(strcmp(fs.f_mntonname, "/")==0 || strcmp(fs.f_mntonname, "/Developer")==0) {
			return;
		}
	}

	NSString* realLoadPath = @(realfilepath);

	DEBUG_LOG("loadPath = %s, \n\tresolvedLoadPath = %s, \n\trealLoadPath = %s\n", loadPath.fileSystemRepresentation, resolvedLoadPath.fileSystemRepresentation, realLoadPath.fileSystemRepresentation);

	if([fileCaches containsObject:realLoadPath]) {
		DEBUG_LOG("Skipping already parsed file: %s", realLoadPath.fileSystemRepresentation);
		return; // Already parsed
	}
	//add realLoadPath to fileCaches
	[fileCaches addObject:realLoadPath];
	
	ensure_jbroot_symlink(realLoadPath.fileSystemRepresentation);

	Fat *fat = fat_init_from_path(realLoadPath.fileSystemRepresentation);
	if (!fat) {
		JBLogError("Failed to parse fat binary at path: %s", realLoadPath.fileSystemRepresentation);
		*result = -1;
		return;
	}

	MachO *macho = NULL;
	if ([loadPath isEqualToString:mainExecutablePath]) {
		if (preferredArch->Count > 0) {
			for (size_t i = 0; i < preferredArch->Count; i++) {
				if (preferredArch->Types[i] != 0 && preferredArch->Subtypes[i] != UINT32_MAX) {
					macho = fat_find_slice(fat, preferredArch->Types[i], preferredArch->Subtypes[i]);
					if (macho) break;
				}
			}
		}
	}
	if (!macho) {
		macho = fat_find_preferred_slice(fat);
		if (!macho) {
			JBLogError("Failed to find preferred slice for file: %s", realLoadPath.fileSystemRepresentation);
			*result = -1;
			fat_free(fat);
			return;
		}
	}

	// Calculate cdhash and add it to our array
	bool cdhashWasKnown = true;
	bool isAdhocSigned = false;
	cdhash_t cdhash = {0};
	int signatureResult = macho_collect_adhoc_cdhash(macho, cdhash);
	if (signatureResult < 0) *result = -1;
	isAdhocSigned = signatureResult == 1;
	if (isAdhocSigned && !cdhashesContains(cdhash)) {
		if (!is_cdhash_trustcached(cdhash)) {
			// Dependencies may have changed even when this image is already trusted.
			int ret = ensure_randomized_cdhash_for_slice(realLoadPath.fileSystemRepresentation, macho->archDescriptor.offset, cdhash);
			if (ret == 0) {
				cdhashesAdd(cdhash);
			} else {
				JBLogError("ensure_randomized_cdhash_for_slice(%llx) failed: %s -> (%d)", macho->archDescriptor.offset, realLoadPath.fileSystemRepresentation, ret);
				*result = ret;
			}
		}
		cdhashWasKnown = false;
	}

	if (*result != 0 || cdhashWasKnown || // If we already knew the cdhash, we can skip parsing dependencies
		!isAdhocSigned) { // If it was not ad hoc signed, we can safely skip it aswell
		fat_free(fat);
		return;
	}

	// Recurse this block on all dependencies
	int dependencyResult = macho_enumerate_dependencies(macho, ^(const char *pathCStr, uint32_t cmd, struct dylib* dylib, bool *stop) {

		NSMutableArray* nextChain = rpathStack.mutableCopy;
		[nextChain addObject:realLoadPath]; //Loading dependencies, add current macho itself to the rpath stack
		
		recurse_handler(@(pathCStr), realLoadPath, mainExecutablePath, workingDir, fileCaches, nextChain, preferredArch, cdhashesOut, cdhashCountOut, result);
		if (*result != 0) *stop = true;
	});
	if (dependencyResult != 0) *result = dependencyResult;

	fat_free(fat);
	
} //autoreleasepool
}

int recurse_collect_untrusted_cdhashes(const char *path, const char *callerImagePath, const char *callerExecutablePath, const char *workingDir, preferredArchInfo* preferredArch, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	if (!cdhashesOut || !cdhashCountOut) return -1;
	*cdhashesOut = NULL;
	*cdhashCountOut = 0;
	if (!path) return -1;
	if(!callerExecutablePath) {
		callerExecutablePath = path;
	}

	NSMutableArray* rpathStack = [NSMutableArray array];

	[rpathStack addObject:@(callerExecutablePath)]; //initial rpath stack
	
	if(callerImagePath && strcmp(callerImagePath, callerExecutablePath) != 0) {
		[rpathStack addObject:@(callerImagePath)];
	}

	if(!callerImagePath) {
		callerImagePath = path;
	}

	NSMutableArray* fileCaches = [NSMutableArray array];

	int result = 0;
	recurse_handler(@(path), @(callerImagePath), @(callerExecutablePath), workingDir ? @(workingDir) : nil, fileCaches, rpathStack, preferredArch, cdhashesOut, cdhashCountOut, &result);
	if (result != 0) {
		free(*cdhashesOut);
		*cdhashesOut = NULL;
		*cdhashCountOut = 0;
	}

	DEBUG_LOG("fileCaches: %s", path, fileCaches.description.UTF8String);
	DEBUG_LOG("Finished collecting cdhashes for path: %s, found %u cdhashes, processed %d files", path, *cdhashCountOut, fileCaches.count);
	return result;
}
