// This is free and unencumbered software released into the public domain.
// For more information, please refer to <http://unlicense.org/>

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "FileCache.h"

#ifndef FILE_CACHE_DEBUG
#define FILE_CACHE_DEBUG    0
#endif

@implementation FileCache {
    BOOL _notificationRegistered;
    BOOL _removing;
    NSDate *_removedAt;
}

- (instancetype)init
{
    return [self initWithPathComponent:@"9049773f-1c14-49d7-a9a1-b63a168b19c9"];
}

- (instancetype)initWithPathComponent:(NSString *)pathComponent
{
    self = [super init];
    if (self) {
        _notificationRegistered = NO;
        _removing = NO;
        _removedAt = nil;
        self.cacheDirectory = [[[self class] cacheDirectory] stringByAppendingPathComponent:pathComponent];
        self.defaultCacheLifetime = 24 * 60 * 60;       // A day
        self.maxCacheLifetime = 7 * 24 * 60 * 60;       // A week
        self.autoRemoveExpiredCacheInterval = 10; //60 * 60;  // A hour
    }
    return self;
}

- (void)dealloc
{
    if (_notificationRegistered) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    }
}

- (void)registerNotificationHandler
{
    @synchronized(self) {
        if (_notificationRegistered) {
            return;
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeExpiredCaches) name:UIApplicationWillEnterForegroundNotification object:nil];
        _notificationRegistered = YES;
    }
}

- (void)unregisterNotificationHandler
{
    @synchronized(self) {
        if (!_notificationRegistered) {
            return;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
        _notificationRegistered = NO;
    }
}

#pragma mark - Properties

- (void)setMaxCacheLifetime:(NSTimeInterval)maxCacheLifetime
{
    [self willChangeValueForKey:@"maxCacheLifetime"];
    _maxCacheLifetime = maxCacheLifetime;
    
    if (maxCacheLifetime > 0) {
        [self registerNotificationHandler];
    } else {
        [self unregisterNotificationHandler];
    }
    
    [self didChangeValueForKey:@"maxCacheLifetime"];
}

#pragma mark - Helper methods

- (NSString *)sha256:(NSString *)aString
{
    const char *s = [aString cStringUsingEncoding:NSASCIIStringEncoding];
    NSData *keyData = [NSData dataWithBytes:s length:strlen(s)];
    
    uint8_t digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(keyData.bytes, (CC_LONG)keyData.length, digest);
    
    char *buf = malloc(CC_SHA256_DIGEST_LENGTH * 2 + 1);
    if (!buf) {
        abort();
    }
    bzero(buf, CC_SHA256_DIGEST_LENGTH * 2 + 1);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) {
        snprintf(&buf[i*2], 3, "%02x", (unsigned int)(digest[i]));
    }
    
    NSString *hash = [[NSString alloc] initWithBytesNoCopy:buf length:CC_SHA256_DIGEST_LENGTH * 2 encoding:NSASCIIStringEncoding freeWhenDone:YES];
    return hash;
}

- (NSString *)pathWithKey:(NSObject <NSCopying> *)aKey
{
    NSString *path = self.cacheDirectory;
    
    NSString *sKey = [self sha256:[aKey description]];
    NSString *p1 = [sKey substringWithRange:NSMakeRange(0, 2)];
    NSString *p2 = [sKey substringWithRange:NSMakeRange(2, 2)];
    NSString *p3 = [sKey substringFromIndex:4];
    
    path = [path stringByAppendingPathComponent:p1];
    path = [path stringByAppendingPathComponent:p2];
    path = [path stringByAppendingPathComponent:p3];
#if FILE_CACHE_DEBUG
    NSLog(@"Path for key %@: %@", aKey, path);
#endif
    return path;
}

#pragma mark - NSDictionary emuration

- (id)objectForKey:(NSObject <NSCopying> *)aKey
{
    return [self objectForKey:aKey cacheLifetime:self.defaultCacheLifetime];
}

- (id)objectForKey:(NSObject <NSCopying> *)aKey cacheLifetime:(NSTimeInterval)cacheLifetime
{
    NSString *path = [self pathWithKey:aKey];
    
    // Missing file
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attrs = [fileManager attributesOfItemAtPath:path error:nil];
    if (!attrs) {
#if FILE_CACHE_DEBUG
        NSLog(@"Missing attribute for %@", aKey);
#endif
        return nil;
    }
    
    if (cacheLifetime == 0.0) {
        cacheLifetime = self.defaultCacheLifetime;
    }
    
    if (cacheLifetime > 0.0) {
        if (cacheLifetime > self.maxCacheLifetime && self.maxCacheLifetime > 0.0) {
            cacheLifetime = self.maxCacheLifetime;
        }
            
        NSDate *moddate = attrs[NSFileModificationDate];
        if (moddate == nil) {
#if FILE_CACHE_DEBUG
            NSLog(@"Missing NSFileModificationDate for %@", aKey);
#endif
            return nil;
        }
        NSDate *date = [moddate dateByAddingTimeInterval:cacheLifetime];
        NSDate *now = [NSDate date];
        // Expired
        NSComparisonResult rv = [now compare:date];
        if (rv == NSOrderedDescending) {
#if FILE_CACHE_DEBUG
            NSLog(@"Cache expired for %@: %@ %lf", aKey, moddate, cacheLifetime);
#endif
            return nil;
        }
    }

#if FILE_CACHE_DEBUG
    NSLog(@"Got cache for %@ from %@", aKey, path);
#endif
    return [FileCache getObjectFromPath:path error:nil];
}

- (void)setObject:(id <NSCoding>)aObject forKey:(NSObject <NSCopying> *)aKey
{
    NSString *path = [self pathWithKey:aKey];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSError *error = nil;
    if (![fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Failed to create cache directory: %@", error);
        return;
    }
    
#if FILE_CACHE_DEBUG
    NSLog(@"Save cache %@ to %@", aKey, path);
#endif
    [FileCache setObject:aObject toPath:path error:nil];
}

- (id)objectForKeyedSubscript:(id)key
{
    return [self objectForKey:key];
}

- (void)setObject:(id)object forKeyedSubscript:(id)key
{
    return [self setObject:object forKey:key];
}

- (void)removeObjectForKey:(NSObject <NSCopying> *)aKey
{
    NSString *path = [self pathWithKey:aKey];
    
#if FILE_CACHE_DEBUG
    NSLog(@"Remove cache %@ to %@", aKey, path);
#endif
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fileManager removeItemAtPath:path error:&error]) {
        NSLog(@"Failed to remove cache directory: %@", error);
        return;
    }
}

#pragma mark - Expire cached files

- (void)removeExpiredCaches
{
    NSTimeInterval cacheLifetime = self.maxCacheLifetime;
    if (cacheLifetime == 0) {
#if FILE_CACHE_DEBUG
        NSLog(@"Return removeExpiredCaches because maxCacheLifetime is 0");
#endif
        return;
    }
    
    NSDate *now = [NSDate date];
    if (_removedAt) {
        NSDate *date = [_removedAt dateByAddingTimeInterval:self.autoRemoveExpiredCacheInterval];
        NSComparisonResult rv = [now compare:date];
        if (rv == NSOrderedAscending) {
#if FILE_CACHE_DEBUG
            NSLog(@"Return removeExpiredCaches by autoRemoveExpiredCacheInterval");
#endif
            return;
        }
    }
    
    @synchronized(self) {
        if (_removing) {
            return;
        }
        _removing = YES;
        _removedAt = [NSDate date];
    }
    
    NSString *dir = self.cacheDirectory;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:dir];
    if (!dirEnum) {
        NSLog(@"Return removeExpiredCaches by enumeratorAtPath returns nil");
        return;
    }
    
#if FILE_CACHE_DEBUG
    NSLog(@"Begin expiring");
#endif
    NSString *file;
    while ((file = [dirEnum nextObject])) {
        NSString *path = [dir stringByAppendingPathComponent:file];
        NSDictionary *attrs = [fileManager attributesOfItemAtPath:path error:nil];
        if (!attrs || attrs[NSFileType] != NSFileTypeRegular) {
            continue;
        }
        
        NSDate *date = attrs[NSFileModificationDate];
        if (date != nil) {
            date = [date dateByAddingTimeInterval:cacheLifetime];
            // Expired
            NSComparisonResult rv = [now compare:date];
            if (rv != NSOrderedDescending) {
                continue;
            }
        }
        
#if FILE_CACHE_DEBUG
        NSLog(@"Removing cache %@", path);
#endif
        NSError *error = nil;
        if (![fileManager removeItemAtPath:path error:&error]) {
            NSLog(@"Failed to remove cache file: %@", error);
        }
    }
    
#if FILE_CACHE_DEBUG
    NSLog(@"End expiring");
#endif
    
    @synchronized(self) {
        _removing = NO;
        _removedAt = [NSDate date];
    }
}

- (void)removeExpiredCachesInBackgroundThread
{
    NSTimeInterval cacheLifetime = self.maxCacheLifetime;
    if (cacheLifetime == 0) {
#if FILE_CACHE_DEBUG
        NSLog(@"Return removeExpiredCaches because maxCacheLifetime is 0");
#endif
        return;
    }
    
    FileCache * __weak weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [weakSelf removeExpiredCaches];
    });
}

#pragma mark - Static methods

+ (NSString *)cacheDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *path = [paths lastObject];
    return path;
}

+ (id)getObjectFromPath:(NSString *)path error:(NSError * __autoreleasing *)error
{
    NSError *e = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&e];
    if (!data) {
#if DEBUG
        if (!([e.domain isEqualToString:NSCocoaErrorDomain] && e.code == 260)) {
            NSLog(@"%@", e);
        }
#endif
        if (error) {
            *error = e;
        }
        return nil;
    }
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
}

+ (BOOL)setObject:(id <NSCoding>)aObject toPath:(NSString *)path error:(NSError * __autoreleasing *)error
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:aObject];
    NSError *e = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&e]) {
#if DEBUG
        NSLog(@"%@", e);
#endif
        if (error) {
            *error = e;
        }
        return NO;
    }
    return YES;
}

+ (FileCache *)sharedCache
{
    static FileCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[FileCache alloc] init];
    });
    return cache;
}

@end
