#pragma once

#import <Foundation/Foundation.h>

static inline BOOL DOCustomMountPathsOverlap(NSString *first, NSString *second)
{
    return [first hasPrefix:[second stringByAppendingString:@"/"]] ||
        [second hasPrefix:[first stringByAppendingString:@"/"]];
}

static inline NSString *DOCustomMountConflictingPath(NSString *path, NSArray *paths)
{
    for (id other in paths) {
        if ([other isKindOfClass:NSString.class] && DOCustomMountPathsOverlap(path, other))
            return other;
    }
    return nil;
}

static inline BOOL DOCustomMountHasSavedDescendant(NSString *path, NSArray *paths)
{
    for (id other in paths) {
        if ([other isKindOfClass:NSString.class] &&
            [other hasPrefix:[path stringByAppendingString:@"/"]])
            return YES;
    }
    return NO;
}

// Old overlapping lists must still be editable and removable without losing data.
static inline BOOL DOCustomMountIntroducesOverlap(NSArray *paths, NSArray *previous)
{
    for (NSString *path in paths) {
        if (![previous containsObject:path] && DOCustomMountConflictingPath(path, paths))
            return YES;
    }
    return NO;
}

static inline NSString *DOCustomMountRetainedAncestor(NSString *path, NSArray *paths)
{
    for (id other in paths) {
        if ([other isKindOfClass:NSString.class] &&
            [path hasPrefix:[other stringByAppendingString:@"/"]])
            return other;
    }
    return nil;
}

static inline BOOL DOCustomMountDropsChildBeforeParent(NSArray *paths, NSArray *previous)
{
    for (id path in previous) {
        if ([path isKindOfClass:NSString.class] && ![paths containsObject:path] &&
            DOCustomMountRetainedAncestor(path, paths))
            return YES;
    }
    return NO;
}
