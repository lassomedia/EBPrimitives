#import <Foundation/Foundation.h>

@interface EBReadWriteLock : NSObject
- (void)lockForReading;
- (void)lockForWriting;
- (void)unlock;
@end