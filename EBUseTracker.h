#import <Foundation/Foundation.h>

@interface EBUseTracker : NSObject
/* ## Accessors */
@property(nonatomic, readonly) NSUInteger count;

/* ## Methods */
/* EBUseTracker holds strong refernces to objects */
- (void)usedObject: (id <NSObject>)object;
- (void)removeObject: (id <NSObject>)object;

- (id <NSObject>)mostRecentlyUsedObject;
- (id <NSObject>)popMostRecentlyUsedObject;
- (id <NSFastEnumeration>)mostRecentlyUsedObjectEnumerator;

- (id <NSObject>)leastRecentlyUsedObject;
- (id <NSObject>)popLeastRecentlyUsedObject;
- (id <NSFastEnumeration>)leastRecentlyUsedObjectEnumerator;
@end