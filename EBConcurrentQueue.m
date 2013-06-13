#import "EBConcurrentQueue.h"
#import <libkern/OSAtomic.h>
#import <EBFoundation/EBFoundation.h>

@implementation EBConcurrentQueue
{
    dispatch_queue_t _queue;
    OSSpinLock _lock;
    NSMutableArray *_blockQueue;
    NSUInteger _semaphore;
}

#pragma mark - Creation -
- (id)init
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

- (id)initWithConcurrentOperationLimit: (NSUInteger)concurrentOperationLimit priority: (dispatch_queue_priority_t)priority
{
        NSParameterAssert(concurrentOperationLimit);
    
    if (!(self = [super init]))
        return nil;
    
    _concurrentOperationLimit = concurrentOperationLimit;
    
    _queue = dispatch_queue_create([[NSString stringWithFormat: @"so.las.%@", NSStringFromClass([self class])] UTF8String], DISPATCH_QUEUE_CONCURRENT);
    dispatch_set_target_queue(_queue, dispatch_get_global_queue(priority, 0));
    
    _lock = OS_SPINLOCK_INIT;
    _blockQueue = [NSMutableArray new];
    _semaphore = _concurrentOperationLimit;
    
    return self;
}

- (void)enqueueBlock: (EBConcurrentQueueBlock)block
{
        NSParameterAssert(block);
    
    BOOL dispatchBlock = NO;
    OSSpinLockLock(&_lock);
    
        /* If our semaphore isn't exhausted, consume one reference and dispatch the block immediately. */
        if (_semaphore)
        {
            _semaphore--;
            dispatchBlock = YES;
        }
        
        /* Otherwise, if our semaphore is exhausted, add the block to the queue. */
        else
            [_blockQueue addObject: block];
    
    OSSpinLockUnlock(&_lock);
    
    if (dispatchBlock)
        [self dispatchBlock: block];
}

- (void)dispatchBlock: (EBConcurrentQueueBlock)block
{
        NSParameterAssert(block);
    
    dispatch_async(_queue,
        ^{
            block();
            
            EBConcurrentQueueBlock queuedBlock = nil;
            OSSpinLockLock(&_lock);
            
                /* If there's a queue of blocks waiting to be executed, pop the first one off and dispatch it! */
                if ([_blockQueue count])
                {
                    queuedBlock = [_blockQueue objectAtIndex: 0];
                    [_blockQueue removeObjectAtIndex: 0];
                }
                
                /* If there isn't a queue of blocks, then we'll simply increment the semaphore. */
                else
                    _semaphore++;
            
            OSSpinLockUnlock(&_lock);
            
            if (queuedBlock)
                [self dispatchBlock: queuedBlock];
        });
}

@end