#import "EBTwoLevelCache.h"
#import <EBFoundation/EBFoundation.h>
#import "EBDiskCache.h"

@implementation EBTwoLevelCache

#pragma mark - Creation -
- (instancetype)initWithMemoryCache: (NSCache *)memoryCache diskCache: (EBDiskCache *)diskCache transformer: (NSValueTransformer *)transformer
{
        NSParameterAssert(memoryCache);
        NSParameterAssert(diskCache);
    
    if (!(self = [super init]))
        return nil;
    
    _memoryCache = memoryCache;
    _diskCache = diskCache;
    _transformer = transformer;
    
    if (!_transformer)
        _transformer = [EBBlockValueTransformer newWithForwardBlock: ^(id value)
            {
                return value;
            }];
    
    return self;
}

- (instancetype)init
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

#pragma mark - Methods -
- (id <NSObject>)objectForKey: (NSString *)key
{
        NSParameterAssert(key);
    
    /* Consult the memory cache for an object for our key. If no object exists, we'll dive down to the disk cache and get its raw data. */
    id <NSObject> result = [_memoryCache objectForKey: key];
        EBConfirmOrPerform(!result, return result);
    
    /* Get the raw data from the disk cache. If no data exists, then simply return nil. */
    NSData *resultData = [_diskCache dataForKey: key];
        EBConfirmOrPerform(resultData, return nil);
    
    /* Transform the raw data into an object. */
    result = [_transformer transformedValue: resultData];
        EBAssertOrRecover(result, return nil);
    
    /* Put our new object in the memory cache and return it. */
    [_memoryCache setObject: result forKey: key];
    return result;
}

- (void)setObject: (id <NSObject>)object forKey: (NSString *)key
{
        NSParameterAssert(object);
        NSParameterAssert(key);
    
    /* Put the object in our memory cache. */
    [_memoryCache setObject: object forKey: key];
    
    /* If our transformer supports reverse transformation, then convert the object into data and place it in our disk cache. */
    if ([[_transformer class] allowsReverseTransformation])
    {
        NSData *objectData = [_transformer reverseTransformedValue: object];
            EBAssertOrRecover(objectData, EBNoOp);
        
        if (objectData)
            [_diskCache setData: objectData forKey: key];
    }
}

@end