#import <Foundation/Foundation.h>

typedef void(^EBConcurrentQueueBlock)(void);

@interface EBConcurrentQueue : NSObject

/* Creation */
- (id)initWithConcurrentOperationLimit: (NSUInteger)concurrentOperationLimit priority: (dispatch_queue_priority_t)priority;

/* Properties */
@property(nonatomic, readonly) NSUInteger concurrentOperationLimit;
@property(nonatomic, readonly) dispatch_queue_priority_t priority;

/* Methods */
- (void)enqueueBlock: (EBConcurrentQueueBlock)block;

@end