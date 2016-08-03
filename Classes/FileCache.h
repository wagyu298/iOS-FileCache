// This is free and unencumbered software released into the public domain.
// For more information, please refer to <http://unlicense.org/>

#import <Foundation/Foundation.h>

@interface FileCache : NSObject

@property (nonatomic, strong) NSString *cacheDirectory;

@property (nonatomic) NSTimeInterval defaultCacheLifetime;
@property (nonatomic) NSTimeInterval maxCacheLifetime;

@property (nonatomic) NSTimeInterval autoRemoveExpiredCacheInterval;

- (instancetype)initWithPathComponent:(NSString *)pathComponent;

- (id)objectForKey:(NSObject <NSCopying> *)aKey;
- (id)objectForKey:(NSObject <NSCopying> *)aKey cacheLifetime:(NSTimeInterval)cacheLifetime;
- (void)setObject:(id <NSCoding>)aObject forKey:(NSObject <NSCopying> *)aKey;

- (id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)object forKeyedSubscript:(id)key;
- (void)removeObjectForKey:(NSObject <NSCopying> *)aKey;

- (void)removeExpiredCaches;

+ (NSString *)cacheDirectory;
+ (id)getObjectFromPath:(NSString *)path error:(NSError * __autoreleasing *)error;
+ (BOOL)setObject:(id <NSCoding>)aObject toPath:(NSString *)path error:(NSError * __autoreleasing *)error;

+ (FileCache *)sharedCache;

@end
