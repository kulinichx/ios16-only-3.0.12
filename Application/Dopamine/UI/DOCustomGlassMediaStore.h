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
    NSURL *url = DOCustomGlassMediaStoreFileURL(filename);
    if (url)
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
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

    NSString *newFilename = [NSString stringWithFormat:@"%@-%@.jpg",
                             filenamePrefix,
                             NSUUID.UUID.UUIDString];
    NSURL *newURL = DOCustomGlassMediaStoreFileURL(newFilename);
    if (!newURL)
        return nil;

    NSError *writeError = nil;
    BOOL wrote = [imageData writeToURL:newURL options:NSDataWritingAtomic error:&writeError];
    if (!wrote) {
        NSLog(@"[CustomGlass][MediaStore] write failed %@: %@", newURL.path, writeError);
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
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
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

    NSString *newVideoFilename = [NSString stringWithFormat:@"wallpaper-video-%@.%@",
                                  NSUUID.UUID.UUIDString,
                                  extension];
    NSURL *newVideoURL = DOCustomGlassMediaStoreFileURL(newVideoFilename);
    if (!newVideoURL)
        return NO;

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
        [[NSFileManager defaultManager] removeItemAtURL:newVideoURL error:nil];
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
        [[NSFileManager defaultManager] removeItemAtURL:newVideoURL error:nil];
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
