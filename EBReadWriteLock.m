#import "EBReadWriteLock.h"
#import <pthread.h>
#import <EBFoundation/EBFoundation.h>

@implementation EBReadWriteLock
{
    pthread_rwlock_t _lock;
}

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    int pthreadResult = pthread_rwlock_init(&_lock, nil);
        EBAssertOrRecover(!pthreadResult, return nil);
    
    return self;
}

- (void)dealloc
{
    int pthreadResult = pthread_rwlock_destroy(&_lock);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
}

- (void)lockForReading
{
    int pthreadResult = pthread_rwlock_rdlock(&_lock);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
}

- (void)lockForWriting
{
    int pthreadResult = pthread_rwlock_wrlock(&_lock);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
}

- (void)unlock
{
    int pthreadResult = pthread_rwlock_unlock(&_lock);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
}

@end