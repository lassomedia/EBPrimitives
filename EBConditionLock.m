#import "EBConditionLock.h"
#import <pthread.h>
#import <sys/time.h>
#import <EBFoundation/EBFoundation.h>

#define EBExactlyOneBitSet(x) ((x) > 0 && ((x) & ((x) - 1)) == 0)
#define EBAtLeastOneBitSet(x) ((x) != 0)

@implementation EBConditionLock
{
    pthread_mutex_t _pthreadMutex;
    pthread_cond_t _pthreadCondition;
}

#pragma mark - Creation -
- (id)initWithCondition: (uint64_t)condition
{
        NSParameterAssert(EBExactlyOneBitSet(condition));
    
    if (!(self = [super init]))
        return nil;
    
    _condition = condition;
    
    int pthreadResult = pthread_mutex_init(&_pthreadMutex, nil);
        EBAssertOrRecover(!pthreadResult, return nil);
    
    pthreadResult = pthread_cond_init(&_pthreadCondition, nil);
        EBAssertOrRecover(!pthreadResult, return nil);
    
    return self;
}

- (id)init
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

- (void)dealloc
{
    int pthreadResult = 0;
    
    pthreadResult = pthread_cond_destroy(&_pthreadCondition);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
    
    pthreadResult = pthread_mutex_destroy(&_pthreadMutex);
        EBAssertOrRecover(!pthreadResult, EBNoOp);
}

#pragma mark - Methods -
- (void)lock
{
    [self lockOnConditions: UINT64_MAX];
}

- (void)unlock
{
    [self unlockWithCondition: _condition];
}

- (void)lockOnConditions: (uint64_t)conditions
{
        NSParameterAssert(EBAtLeastOneBitSet(conditions));
    
    /* Lock the mutex */
    int pthreadResult = pthread_mutex_lock(&_pthreadMutex);
        EBAssertOrBail(!pthreadResult);
    
    while (!(_condition & conditions))
    {
        pthreadResult = pthread_cond_wait(&_pthreadCondition, &_pthreadMutex);
            EBAssertOrBail(!pthreadResult);
    }
}

- (void)unlockWithCondition: (uint64_t)condition
{
        NSParameterAssert(EBExactlyOneBitSet(condition));
    
    _condition = condition;
    
    /* Relinquish the lock */
    int pthreadResult = pthread_mutex_unlock(&_pthreadMutex);
        EBAssertOrBail(!pthreadResult);
    
    /* Let other threads know that the condition changed! */
    pthreadResult = pthread_cond_broadcast(&_pthreadCondition);
        EBAssertOrBail(!pthreadResult);
}

@end