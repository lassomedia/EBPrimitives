#import <Foundation/Foundation.h>

@interface EBDiskCache : NSObject

/* ### Creation */
- (id)initWithStoreURL: (NSURL *)storeURL sizeLimit: (size_t)sizeLimit;

/* ### Properties */
@property(nonatomic, readonly) NSURL *storeURL;
@property(nonatomic, readonly) size_t sizeLimit;

/* ### Methods */
- (BOOL)containsDataForKey: (NSString *)key;
- (NSData *)dataForKey: (NSString *)key;
- (void)setData: (NSData *)data forKey: (NSString *)key;

/* -startAccessForKey: guarantees that if a non-nil URL is returned, the referenced file will remain valid until
   -finishAccess is called. These methods allow the filesystem to be read manually by clients, instead of
   relying on -dataForKey:.
   
   -finishAccess should only be called if -startAccessForKey: returns non-nil.
   -finishAccess may be called from a different thread than its corresponding -startAccessForKey:. */
- (NSURL *)startAccessForKey: (NSString *)key;
- (void)finishAccess;

/* Writes the receiver's data structures to disk. This method is automatically called periodically during the normal use of
   EBDiskCache, but should be called manually upon app background/termination. */
- (void)sync;

/* Waits for all in-progress operations to complete, prevents all future operations from starting, and synchronously deletes
   all files on disk. If an outstanding access is occurring (via -startAccessForKey:) on the calling thread, this method
   will deadlock! */
- (void)destroy;

@end