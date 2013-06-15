#import <Foundation/Foundation.h>
@class EBDiskCache;

@interface EBTwoLevelCache : NSObject

/* ## Creation */
/* Designated initializer */
/* If `transformer` is nil, the resulting object stores and retrieves NSData objects. */
- (instancetype)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache transformer: (NSValueTransformer *)transformer;

/* ## Properties */
@property(nonatomic, readonly) NSCache *memoryCache;
@property(nonatomic, readonly) EBDiskCache *diskCache;
@property(nonatomic, readonly) NSValueTransformer *transformer;

/* ## Methods */

/* Returns the object from the memory cache if it exists, otherwise goes down to the disk cache and transforms
   the data into an object using `transformer`, and then places the object in the memory cache. If no data
   exists, returns nil. */
- (id <NSObject>)objectForKey: (NSString *)key;

/* Puts the object in the memory cache, and if `transformer` supports reverse transformation, the object will
   be converted to data and stored in the disk cache. */
- (void)setObject: (id <NSObject>)object forKey: (NSString *)key;

@end