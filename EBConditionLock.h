#import <Foundation/Foundation.h>

/* EBConditionLock is similar to NSConditionLock, except EBConditionLock permits clients to lock on multiple
   conditions (specified using a bit field), rather than just one.
   
   Condition argument rules:
   'condition': Exactly one bit must be set
   'conditions': One or more bits must be set (non-zero) */

@interface EBConditionLock : NSObject <NSLocking>

/* ### Creation */
- (id)initWithCondition: (uint64_t)condition;

/* ### Properties */
@property(nonatomic, readonly) uint64_t condition;

/* ### Methods */
- (void)lockOnConditions: (uint64_t)conditions;
- (void)unlockWithCondition: (uint64_t)condition;

@end