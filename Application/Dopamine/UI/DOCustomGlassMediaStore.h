//
//  DOCustomGlassMediaStore.h
//  Dopamine
//
//  R14: one storage owner for Custom Glass user media.
//
//  The Dopamine process is privileged, so Foundation user-domain search paths
//  are not used to identify its App Data Container. Resolve the installed app's
//  data container explicitly by bundle identifier, then keep only media
//  filenames in NSUserDefaults.
//

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#import "DOCustomGlassThemeSync.h"

static NSString * const DOCustomGlassMediaStoreAvatarFilenameKey =
    @"DOCustomGlassTheme.AvatarFilename";
static NSString * const DOCustomGlassMediaStoreWallpaperFilenameKey =
    @"DOCustomGlassTheme.WallpaperFilename";
static NSString * const DOCustomGlassMediaStoreWallpaperVideoFilenameKey =
    @"DOCustomGlassTheme.WallpaperVideoFilename";

static inline id DOCustomGlassMediaStoreCallObjectGetter(id object, NSString *selectorName)
{
    SEL selector = NSSelectorFromString(selectorName);
    if (!object || ![object respondsToSelector:selector])
        return nil;

    IMP implementation = [object methodForSelector:selector];
    if (!implementation)
        return nil;

    typedef id (*DOCustomGlassObjectGetterIMP)(id, SEL);
    return ((DOCustomGlassObjectGetterIMP)implementation)(object, selector);
}

static inline NSURL *DOCustomGlassMediaStoreLSContainerURL(NSString *bundleIdentifier)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
               RTLD_LAZY | RTLD_LOCAL);
    });

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL factorySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:factorySelector])
        return nil;

    IMP factoryImplementation = [proxyClass methodForSelector:factorySelector];
    if (!factoryImplementation)
        return nil;

    typedef id (*DOCustomGlassLSFactoryIMP)(id, SEL, NSString *);
    id proxy = ((DOCustomGlassLSFactoryIMP)factoryImplementation)(proxyClass,
                                                                  factorySelector,
                                                                  bundleIdentifier);
    id value = DOCustomGlassMediaStoreCallObjectGetter(proxy, @"dataContainerURL");
    return [value isKindOfClass:NSURL.class] ? (NSURL *)value : nil;
}

static inline NSURL *DOCustomGlassMediaStoreMCMContainerURL(NSString *bundleIdentifier)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager",
               RTLD_LAZY | RTLD_LOCAL);
    });

    Class containerClass = NSClassFromString(@"MCMAppDataContainer");
    SEL selector = NSSelectorFromString(@"containerWithIdentifier:createIfNecessary:existed:error:");
    if (!containerClass || ![containerClass respondsToSelector:selector])
        return nil;

    IMP implementation = [containerClass methodForSelector:selector];
    if (!implementation)
        return nil;

    BOOL existed = NO;
    NSError *error = nil;
    typedef id (*DOCustomGlassMCMFactoryIMP)(id, SEL, NSString *, BOOL, BOOL *, NSError **);
    id container = ((DOCustomGlassMCMFactoryIMP)implementation)(containerClass,
                                                                 selector,
                                                                 bundleIdentifier,
                                                                 NO,
                                                                 &existed,
                                                                 &error);
    id value = DOCustomGlassMediaStoreCallObjectGetter(container, @"url");
    NSURL *url = [value isKindOfClass:NSURL.class] ? (NSURL *)value : nil;
    if (!url && error)
        NSLog(@"[CustomGlass][MediaStore] MCM resolve failed: %@", error);
    return url;
}

static inline NSURL *DOCustomGlassMediaStoreContainerURL(void)
{
    static NSURL *resolvedURL = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        if (bundleIdentifier.length == 0)
            return;

        // LaunchServices describes the installed app registration and exposes
        // its real dataContainerURL without depending on process HOME.
        resolvedURL = DOCustomGlassMediaStoreLSContainerURL(bundleIdentifier);

        // MCM is a second explicit bundle-id -> data-container resolver.
        if (!resolvedURL)
            resolvedURL = DOCustomGlassMediaStoreMCMContainerURL(bundleIdentifier);

        if (resolvedURL)
            NSLog(@"[CustomGlass][MediaStore] container=%@", resolvedURL.path);
        else
            NSLog(@"[CustomGlass][MediaStore] failed to resolve App Data Container for %@",
                  bundleIdentifier);
    });
    return resolvedURL;
}

static inline NSURL *DOCustomGlassMediaStoreDirectoryURL(void)
{
    NSURL *containerURL = DOCustomGlassMediaStoreContainerURL();
    if (!containerURL)
        return nil;

    NSURL *directoryURL = [[[[containerURL
        URLByAppendingPathComponent:@"Library" isDirectory:YES]
        URLByAppendingPathComponent:@"Application Support" isDirectory:YES]
        URLByAppendingPathComponent:@"CustomGlass" isDirectory:YES]
        URLByAppendingPathComponent:@"Media" isDirectory:YES];

    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                                             withIntermediateDirectories:YES
                                                              attributes:nil
                                                                   error:&error];
    if (!created) {
        NSLog(@"[CustomGlass][MediaStore] create directory failed %@: %@",
              directoryURL.path, error);
        return nil;
    }
    return directoryURL;
}

static inline BOOL DOCustomGlassMediaStoreIsSafeFilename(NSString *filename)
{
    return filename.length > 0 &&
           [filename isEqualToString:filename.lastPathComponent] &&
           ![filename isEqualToString:@"."] &&
           ![filename isEqualToString:@".."];
}

// Access only while holding the shared defaults class lock, including across TUs.
static inline NSMutableSet<NSString *> *DOCustomGlassMediaStoreActiveFiles(void)
{
    const void *key = (const void *)NSSelectorFromString(@"do_customGlassActiveMediaFiles");
    NSMutableSet *files = objc_getAssociatedObject(NSUserDefaults.class, key);
    if (!files) {
        files = [NSMutableSet set];
        objc_setAssociatedObject(NSUserDefaults.class, key, files, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return files;
}

static inline NSString *DOCustomGlassMediaStoreReserveFilename(NSString *prefix, NSString *extension)
{
    @synchronized(NSUserDefaults.class) {
        NSString *filename = [NSString stringWithFormat:@"%@-%@.%@", prefix, NSUUID.UUID.UUIDString, extension];
        [DOCustomGlassMediaStoreActiveFiles() addObject:filename];
        return filename;
    }
}

static inline void DOCustomGlassMediaStoreReleaseFilename(NSString *filename)
{
    @synchronized(NSUserDefaults.class) {
        if (filename) [DOCustomGlassMediaStoreActiveFiles() removeObject:filename];
    }
}

static inline BOOL DOCustomGlassMediaStoreIsGeneratedFilename(NSString *filename)
{
    if (!DOCustomGlassMediaStoreIsSafeFilename(filename)) return NO;
    NSString *stem = filename.stringByDeletingPathExtension;
    NSString *extension = filename.pathExtension;
    NSString *prefix = nil;
    if ([stem hasPrefix:@"wallpaper-video-"]) {
        prefix = @"wallpaper-video-";
        if (![@[@"mov", @"mp4", @"m4v"] containsObject:extension]) return NO;
    } else {
        if (![extension isEqualToString:@"jpg"]) return NO;
        if ([stem hasPrefix:@"wallpaper-poster-"]) prefix = @"wallpaper-poster-";
        else if ([stem hasPrefix:@"wallpaper-"]) prefix = @"wallpaper-";
        else if ([stem hasPrefix:@"avatar-"]) prefix = @"avatar-";
    }
    if (!prefix) return NO;
    NSString *identifier = [stem substringFromIndex:prefix.length];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    return uuid && [uuid.UUIDString isEqualToString:identifier];
}

// Nil means the reference state cannot safely authorize any deletion.
static inline NSSet<NSString *> *DOCustomGlassMediaStoreReferencedFiles(void)
{
    NSDictionary *external = [NSDictionary dictionaryWithContentsOfFile:DOCustomGlassThemeSyncPath()];
    id version = external[DOCustomGlassThemeSyncVersionKey];
    if (![version isKindOfClass:NSNumber.class] || ![version isEqual:@1]) return nil;
    NSMutableSet *referenced = [NSMutableSet set];
    for (NSString *key in @[DOCustomGlassMediaStoreAvatarFilenameKey,
                            DOCustomGlassMediaStoreWallpaperFilenameKey,
                            DOCustomGlassMediaStoreWallpaperVideoFilenameKey]) {
        for (id value in @[external[key] ?: NSNull.null,
                           [NSUserDefaults.standardUserDefaults objectForKey:key] ?: NSNull.null]) {
            if (value == NSNull.null) continue;
            if (![value isKindOfClass:NSString.class] || !DOCustomGlassMediaStoreIsSafeFilename(value)) return nil;
            [referenced addObject:value];
        }
    }
    return referenced;
}

static inline NSUInteger DOCustomGlassMediaStorePruneOrphans(void)
{
    NSURL *container = DOCustomGlassMediaStoreContainerURL();
    NSURL *directory = container ? DOCustomGlassMediaStoreDirectoryURL() : nil;
    if (!directory) return 0;
    NSString *expected = [container.path.stringByResolvingSymlinksInPath
        stringByAppendingPathComponent:@"Library/Application Support/CustomGlass/Media"];
    if (![directory.path.stringByResolvingSymlinksInPath isEqualToString:expected]) return 0;

    int flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC;
    int descriptor = open(container.path.stringByResolvingSymlinksInPath.fileSystemRepresentation, flags);
    if (descriptor < 0) return 0;
    for (NSString *component in @[@"Library", @"Application Support", @"CustomGlass", @"Media"]) {
        int next = openat(descriptor, component.fileSystemRepresentation, flags);
        close(descriptor);
        if (next < 0) return 0;
        descriptor = next;
    }
    DIR *entries = fdopendir(descriptor);
    if (!entries) { close(descriptor); return 0; }
    NSUInteger removed = 0;
    NSTimeInterval cutoff = NSDate.date.timeIntervalSince1970 - (24.0 * 60.0 * 60.0);
    struct dirent *entry;
    while ((entry = readdir(entries))) {
        @autoreleasepool {
            NSString *filename = [NSString stringWithUTF8String:entry->d_name];
            if (!DOCustomGlassMediaStoreIsGeneratedFilename(filename)) continue;
            @synchronized(NSUserDefaults.class) {
                if ([DOCustomGlassMediaStoreActiveFiles() containsObject:filename]) continue;
                NSSet *referenced = DOCustomGlassMediaStoreReferencedFiles();
                if (!referenced) break;
                if ([referenced containsObject:filename]) continue;
                struct stat info;
                // One immediate child only: never recurse or follow a link.
                if (fstatat(descriptor, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0 ||
                    !S_ISREG(info.st_mode) || info.st_mtime > cutoff) continue;
                if (unlinkat(descriptor, entry->d_name, 0) == 0) removed++;
            }
        }
    }
    closedir(entries);
    return removed;
}

static inline void DOCustomGlassMediaStoreScheduleOrphanCleanup(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                NSUInteger removed = DOCustomGlassMediaStorePruneOrphans();
                if (removed) NSLog(@"[CustomGlass][MediaStore] removed orphan files=%lu", (unsigned long)removed);
            }
        });
    });
}

static inline NSURL *DOCustomGlassMediaStoreFileURL(NSString *filename)
{
    if (!DOCustomGlassMediaStoreIsSafeFilename(filename))
        return nil;

    NSURL *directoryURL = DOCustomGlassMediaStoreDirectoryURL();
    return directoryURL ?
        [directoryURL URLByAppendingPathComponent:filename isDirectory:NO] : nil;
}

static inline UIImage *DOCustomGlassMediaStoreLoadImageForDefaultsKey(NSString *defaultsKey)
{
    NSString *filename = [[NSUserDefaults standardUserDefaults] stringForKey:defaultsKey];
    NSURL *fileURL = DOCustomGlassMediaStoreFileURL(filename);
    if (!fileURL)
        return nil;

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileURL
                                        options:NSDataReadingMappedIfSafe
                                          error:&readError];
    UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
    if (!image) {
        NSLog(@"[CustomGlass][MediaStore] load failed key=%@ file=%@ bytes=%lu error=%@",
              defaultsKey,
              filename,
              (unsigned long)data.length,
              readError);
    }
    return image;
}

static inline void DOCustomGlassMediaStoreRemoveFile(NSString *filename)
{
    @synchronized(NSUserDefaults.class) {
        NSURL *url = DOCustomGlassMediaStoreFileURL(filename);
        if (url)
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        DOCustomGlassMediaStoreReleaseFilename(filename);
    }
}

static inline BOOL DOCustomGlassMediaStoreCommit(NSDictionary<NSString *, id> *changes,
                                                 NSProgress *request)
{
    @synchronized(NSUserDefaults.class) {
        if (!request || request.cancelled)
            return NO;

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSMutableArray<NSString *> *replacedFiles = [NSMutableArray array];
        for (NSString *key in changes) {
            NSString *old = [defaults stringForKey:key];
            if (old && ![old isEqual:changes[key]])
                [replacedFiles addObject:old];
        }
        if (!DOCustomGlassThemeSyncCommitChanges(changes))
            return NO;

        // A file shared by two references must survive until both release it.
        NSMutableSet *referenced = [NSMutableSet set];
        for (NSString *key in @[DOCustomGlassMediaStoreAvatarFilenameKey,
                                DOCustomGlassMediaStoreWallpaperFilenameKey,
                                DOCustomGlassMediaStoreWallpaperVideoFilenameKey]) {
            NSString *filename = [defaults stringForKey:key];
            if (filename)
                [referenced addObject:filename];
        }
        for (NSString *filename in replacedFiles) {
            if (![referenced containsObject:filename])
                DOCustomGlassMediaStoreRemoveFile(filename);
        }
        for (id value in changes.allValues) {
            if ([value isKindOfClass:NSString.class])
                DOCustomGlassMediaStoreReleaseFilename(value);
        }
        return YES;
    }
}

static inline NSString *DOCustomGlassMediaStoreStageImage(UIImage *image,
                                                          NSString *filenamePrefix,
                                                          UIImage **persistedImage)
{
    NSData *imageData = image ? UIImageJPEGRepresentation(image, 0.92) : nil;
    if (imageData.length == 0)
        return nil;

    NSString *newFilename = DOCustomGlassMediaStoreReserveFilename(filenamePrefix, @"jpg");
    NSURL *newURL = DOCustomGlassMediaStoreFileURL(newFilename);
    if (!newURL) {
        DOCustomGlassMediaStoreReleaseFilename(newFilename);
        return nil;
    }

    NSError *writeError = nil;
    BOOL wrote = [imageData writeToURL:newURL options:NSDataWritingAtomic error:&writeError];
    if (!wrote) {
        NSLog(@"[CustomGlass][MediaStore] write failed %@: %@", newURL.path, writeError);
        DOCustomGlassMediaStoreRemoveFile(newFilename);
        return nil;
    }

    NSError *readError = nil;
    NSData *persistedData = [NSData dataWithContentsOfURL:newURL
                                                 options:NSDataReadingMappedIfSafe
                                                   error:&readError];
    UIImage *decodedImage = persistedData.length > 0 ?
        [UIImage imageWithData:persistedData] : nil;
    if (!decodedImage) {
        NSLog(@"[CustomGlass][MediaStore] verify failed %@ bytes=%lu error=%@",
              newURL.path,
              (unsigned long)persistedData.length,
              readError);
        DOCustomGlassMediaStoreRemoveFile(newFilename);
        return nil;
    }

    if (persistedImage)
        *persistedImage = decodedImage;
    return newFilename;
}

static inline UIImage *DOCustomGlassMediaStoreLoadAvatar(void)
{
    return DOCustomGlassMediaStoreLoadImageForDefaultsKey(
        DOCustomGlassMediaStoreAvatarFilenameKey);
}

static inline BOOL DOCustomGlassMediaStoreSaveAvatar(UIImage *image, NSProgress *request,
                                                     UIImage **persistedImage)
{
    if (!request || request.cancelled)
        return NO;
    UIImage *decodedImage = nil;
    NSString *filename = DOCustomGlassMediaStoreStageImage(image, @"avatar", &decodedImage);
    if (!filename)
        return NO;
    if (!DOCustomGlassMediaStoreCommit(@{DOCustomGlassMediaStoreAvatarFilenameKey: filename}, request)) {
        DOCustomGlassMediaStoreRemoveFile(filename);
        return NO;
    }
    if (persistedImage)
        *persistedImage = decodedImage;
    return YES;
}

static inline NSURL *DOCustomGlassMediaStoreLoadWallpaperVideoURL(void)
{
    NSString *filename = [[NSUserDefaults standardUserDefaults]
        stringForKey:DOCustomGlassMediaStoreWallpaperVideoFilenameKey];
    NSURL *fileURL = DOCustomGlassMediaStoreFileURL(filename);
    if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path])
        return nil;
    return fileURL;
}

static inline UIImage *DOCustomGlassMediaStoreLoadWallpaper(void)
{
    return DOCustomGlassMediaStoreLoadImageForDefaultsKey(
        DOCustomGlassMediaStoreWallpaperFilenameKey);
}

static inline BOOL DOCustomGlassMediaStoreSaveWallpaper(UIImage *image, NSProgress *request,
                                                        UIImage **persistedImage)
{
    if (!request || request.cancelled)
        return NO;
    UIImage *decodedImage = nil;
    NSString *filename = DOCustomGlassMediaStoreStageImage(image, @"wallpaper", &decodedImage);
    if (!filename)
        return NO;
    NSDictionary *changes = @{DOCustomGlassMediaStoreWallpaperFilenameKey: filename,
                             DOCustomGlassMediaStoreWallpaperVideoFilenameKey: NSNull.null};
    if (!DOCustomGlassMediaStoreCommit(changes, request)) {
        DOCustomGlassMediaStoreRemoveFile(filename);
        return NO;
    }
    if (persistedImage)
        *persistedImage = decodedImage;
    return YES;
}

static inline BOOL DOCustomGlassMediaStoreSaveWallpaperVideo(NSURL *sourceURL,
                                                              UIImage *posterImage,
                                                              NSProgress *request,
                                                              UIImage **persistedPosterImage)
{
    if (!sourceURL.isFileURL || !posterImage || !request || request.cancelled)
        return NO;

    NSString *extension = sourceURL.pathExtension.lowercaseString;
    NSSet<NSString *> *supportedExtensions = [NSSet setWithArray:@[@"mov", @"mp4", @"m4v"]];
    if (![supportedExtensions containsObject:extension])
        extension = @"mov";

    NSString *newVideoFilename = DOCustomGlassMediaStoreReserveFilename(@"wallpaper-video", extension);
    NSURL *newVideoURL = DOCustomGlassMediaStoreFileURL(newVideoFilename);
    if (!newVideoURL) {
        DOCustomGlassMediaStoreReleaseFilename(newVideoFilename);
        return NO;
    }

    NSError *copyError = nil;
    BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:sourceURL
                                                          toURL:newVideoURL
                                                          error:&copyError];
    if (!copied) {
        NSLog(@"[CustomGlass][MediaStore] video copy failed %@: %@",
              sourceURL.path, copyError);
        DOCustomGlassMediaStoreRemoveFile(newVideoFilename);
        return NO;
    }

    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:newVideoURL.path error:nil];
    unsigned long long fileSize = [attributes[NSFileSize] unsignedLongLongValue];
    if (fileSize == 0) {
        DOCustomGlassMediaStoreRemoveFile(newVideoFilename);
        return NO;
    }

    // The poster remains the canonical still wallpaper. It gives cold launch,
    // luminance/scrim analysis and UIImage-based refraction a deterministic
    // fallback while AVPlayer owns only the moving presentation layer.
    UIImage *persistedPoster = nil;
    NSString *posterFilename = DOCustomGlassMediaStoreStageImage(posterImage,
                                                                @"wallpaper-poster",
                                                                &persistedPoster);
    if (!posterFilename) {
        DOCustomGlassMediaStoreRemoveFile(newVideoFilename);
        return NO;
    }

    NSDictionary *changes = @{DOCustomGlassMediaStoreWallpaperFilenameKey: posterFilename,
                             DOCustomGlassMediaStoreWallpaperVideoFilenameKey: newVideoFilename};
    if (!DOCustomGlassMediaStoreCommit(changes, request)) {
        DOCustomGlassMediaStoreRemoveFile(posterFilename);
        DOCustomGlassMediaStoreRemoveFile(newVideoFilename);
        return NO;
    }

    NSLog(@"[CustomGlass][MediaStore] saved video file=%@ bytes=%llu",
          newVideoFilename, fileSize);
    if (persistedPosterImage)
        *persistedPosterImage = persistedPoster;
    return YES;
}
