// TODO
// Use LRU (instead of containers approach) to evict data? (Our current algorithm evicts data based on when it was stored in the cache, with the oldest entries that were stored earlier being evicted first.) By using an LRU we should also be able to use a stricter eviction policy based on the size of cache...

#import "EBDiskCache.h"
#import <sys/stat.h>
#import <libkern/OSAtomic.h>
#import <EBFoundation/EBFoundation.h>
#import "EBConditionLock.h"
#import "EBReadWriteLock.h"

typedef enum : uint64_t
{
    EBDiskCacheStateIdle            = 1 << 0, /* Allows everything */
    EBDiskCacheStateUsing           = 1 << 1, /* Prevents Invalid */
    EBDiskCacheStateReading         = 1 << 2, /* Prevents Removing */
    EBDiskCacheStateRemoving        = 1 << 3, /* Prevents Reading */
    EBDiskCacheStateInvalid         = 1 << 4, /* Prevents everything */
} EBDiskCacheState;

@implementation EBDiskCache
{
    NSMutableArray *_containers;
    size_t _firstContainerSize;
    NSUInteger _changeCount;
    EBReadWriteLock *_containersLock;
    
    EBConditionLock *_stateLock;
    NSUInteger _usingCount;
    NSUInteger _readingCount;
    NSUInteger _removingCount;
    
    int32_t _rotationScheduled;
}

static const NSUInteger kContainersCount = 3;
static NSString *const kContainersPlistFileName = @"containers.plist";
static const NSUInteger kSyncNeededChangeCount = 250;

#pragma mark - Creation -
- (instancetype)initWithStoreURL: (NSURL *)storeURL sizeLimit: (size_t)sizeLimit
{
        NSParameterAssert(storeURL);
    
    if (!(self = [super init]))
        return nil;
    
    /* Initialize our ivars */
    _storeURL = storeURL;
    _sizeLimit = sizeLimit;
    
    _containers = [NSMutableArray new];
    for (NSUInteger i = 0; i < kContainersCount; i++)
        [_containers addObject: [NSMutableDictionary new]];
    
    _firstContainerSize = 0;
    _changeCount = 0;
    _containersLock = [EBReadWriteLock new];
    
    _stateLock = [[EBConditionLock alloc] initWithCondition: EBDiskCacheStateIdle];
    _usingCount = 0;
    _readingCount = 0;
    _removingCount = 0;
    
    _rotationScheduled = NO;
    
    /* Verify that our store URL either doesn't exist, or if it does, that it's a directory. */
    NSNumber *isDirectory = nil;
    BOOL getResourceValueResult = [_storeURL getResourceValue: &isDirectory forKey: NSURLIsDirectoryKey error: nil];
        EBAssertOrRecover(!getResourceValueResult || [isDirectory boolValue], return nil);
    
    if (!getResourceValueResult)
    {
        BOOL createDirectoryResult = [[NSFileManager defaultManager] createDirectoryAtURL: _storeURL withIntermediateDirectories: NO attributes: nil error: nil];
            EBAssertOrRecover(createDirectoryResult, return nil);
    }
    
    /* Load our containers from disk and delete any unreferenced files! */
    [self loadContainersAndCleanStoreDirectory];
    return self;
}

- (id)init
{
    EBRaise(@"%@ cannot be initialized via %@!", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return nil;
}

- (void)loadContainersAndCleanStoreDirectory
{
    /* Unarchive the containers plist. */
    NSArray *storedContainers = [[self class] readContainersPlistFromURL: [_storeURL URLByAppendingPathComponent: kContainersPlistFileName]];
    
    /* Sanity-check all the entries in the loaded containers (from the containers.plist file), verifying that each entry's file exists. */
    NSMutableSet *referencedFileNames = [NSMutableSet new];
    BOOL firstContainer = YES;
    NSEnumerator *storedContainersEnumerator = [storedContainers objectEnumerator];
    for (NSMutableDictionary *currentContainer in _containers)
    {
        NSDictionary *storedContainer = [storedContainersEnumerator nextObject];
            /* It's possible that there's fewer stored containers than we need at runtime */
            EBConfirmOrPerform(storedContainer, break);
        
        [storedContainer enumerateKeysAndObjectsUsingBlock:
            ^(NSString *key, NSString *fileName, BOOL *stop)
            {
                    /* Verify that both the key and value are strings. */
                    EBAssertOrRecover(key && [key isKindOfClass: [NSString class]], return);
                    EBAssertOrRecover(fileName && [fileName isKindOfClass: [NSString class]] && [fileName length], return);
                
                const char *const filePath = [[[_storeURL URLByAppendingPathComponent: fileName] path] UTF8String];
                    EBAssertOrRecover(filePath, return);
                
                /* Verify that the file exists and that it's a regular file */
                struct stat fileInfo;
                int statResult = lstat(filePath, &fileInfo);
                    EBAssertOrRecover(!statResult, return);
                    EBAssertOrRecover(S_ISREG(fileInfo.st_mode), return);
                
                /* If we get here, everything checks out, so add the entry. */
                currentContainer[key] = fileName;
                [referencedFileNames addObject: fileName];
                
                if (firstContainer)
                    _firstContainerSize += fileInfo.st_size;
            }];
        
        firstContainer = NO;
    }
    
    /* Delete all files and directories that aren't referenced in any of our containers, using referencedFileNames to tell whether a file is referenced. */
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL: _storeURL
        includingPropertiesForKeys: nil options: NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler: nil];
    for (NSURL *currentFileURL in directoryEnumerator)
    {
        NSString *fileName = [currentFileURL lastPathComponent];
            EBAssertOrRecover(fileName && [fileName length], continue);
            EBConfirmOrPerform(![fileName isEqualToString: kContainersPlistFileName], continue); /* Ignore the info.plist file! */
        
        if (![referencedFileNames containsObject: fileName])
        {
//            #warning debug
//            NSLog(@"WILL DELETE URL: %@", currentFileURL);
            
            BOOL deleteResult = [fileManager removeItemAtURL: currentFileURL error: nil];
            
//            #warning debug
//            NSLog(@"DID DELETE URL (%ju): %@", (uintmax_t)deleteResult, currentFileURL);
            
                EBAssertOrRecover(deleteResult, EBNoOp);
        }
    }
}

#pragma mark - Methods -
- (BOOL)containsDataForKey: (NSString *)key
{
        NSParameterAssert(key);
    
    if ([self startAccessForKey: key])
    {
        [self finishAccess];
        return YES;
    }
    
    return NO;
}

- (NSData *)dataForKey: (NSString *)key
{
        NSParameterAssert(key);
    
    NSURL *url = nil;
    NSData *result = nil;
    
    EBTry:
    {
        url = [self startAccessForKey: key];
            EBConfirmOrPerform(url, goto EBFinish);
        
        result = [NSData dataWithContentsOfURL: url];
            EBAssertOrRecover(result, goto EBFinish);
    }
    
    EBFinish:
    {
        if (url)
            [self finishAccess];
    }
    
    return result;
}

- (void)setData: (NSData *)data forKey: (NSString *)key
{
        NSParameterAssert(data);
        NSParameterAssert(key);
    
    BOOL startStateResult = NO;
    
    EBTry:
    {
        NSString *fileName = [[NSUUID UUID] UUIDString];
            EBAssertOrRecover(fileName && [fileName length], goto EBFinish);
        
        NSURL *fileURL = [_storeURL URLByAppendingPathComponent: fileName];
            EBAssertOrRecover(fileURL, goto EBFinish);
        
        startStateResult = [self startState: EBDiskCacheStateUsing];
            EBConfirmOrPerform(startStateResult, goto EBFinish);
        
        BOOL writeDataResult = [data writeToURL: fileURL atomically: YES];
            EBAssertOrRecover(writeDataResult, goto EBFinish);
        
        size_t dataLength = [data length];
        BOOL sync = NO;
        BOOL rotate = NO;
        [_containersLock lockForWriting];
            ((NSMutableDictionary *)_containers[0])[key] = fileName;
            _firstContainerSize += dataLength;
            
            /* Increment our change count, and if it's greater than our threshold, schedule ourself to be sync'd. */
            _changeCount++;
            if (_changeCount >= kSyncNeededChangeCount)
            {
                _changeCount = 0;
                sync = YES;
            }
            
            /* Schedule a rotation if our first container is greater than our threshold. */
            rotate = (_firstContainerSize > (_sizeLimit / [_containers count]));
        [_containersLock unlock];
        
        if (sync)
        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                ^{
                    [self sync];
                });
        }
        
        if (rotate && OSAtomicCompareAndSwap32(NO, YES, &_rotationScheduled))
        {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
                ^{
                    [self rotate];
                    EBAssertOrBail(OSAtomicCompareAndSwap32(YES, NO, &_rotationScheduled));
                });
        }
    }
    
    EBFinish:
    {
        if (startStateResult)
            [self stopState: EBDiskCacheStateUsing];
    }
}

- (NSURL *)startAccessForKey: (NSString *)key
{
        NSParameterAssert(key);
    
    BOOL startReadingResult = NO;
    NSURL *result = nil;
    
    EBTry:
    {
        startReadingResult = [self startState: EBDiskCacheStateReading];
            EBConfirmOrPerform(startReadingResult, goto EBFinish);
        
        NSString *fileName = nil;
        [_containersLock lockForReading];
            for (NSDictionary *currentContainer in _containers)
            {
                fileName = currentContainer[key];
                if (fileName)
                    break;
            }
        [_containersLock unlock];
        
            /* Verify that we have a filename for the given key */
            EBConfirmOrPerform(fileName, goto EBFinish);
        
        result = [_storeURL URLByAppendingPathComponent: fileName];
            EBAssertOrRecover(result, goto EBFinish);
    }
    
    EBFinish:
    {
        if (startReadingResult && !result)
            [self stopState: EBDiskCacheStateReading];
        
        return result;
    }
}

- (void)finishAccess
{
    [self stopState: EBDiskCacheStateReading];
}

- (void)sync
{
//    #warning debug
//    NSLog(@"### SYNC (START)");
    
    BOOL startStateResult = NO;
    
    EBTry:
    {
        /* We're using -startState: to short-circuit if we've been invalidated, and we're using the Using state because it doesn't
           block any other states, and can occur while in any state. */
        startStateResult = [self startState: EBDiskCacheStateUsing];
            EBConfirmOrPerform(startStateResult, goto EBFinish);
        
        /* Create a thread-local copy of our containers */
        NSMutableArray *containers = [NSMutableArray new];
        [_containersLock lockForReading];
            for (NSDictionary *currentContainer in _containers)
                [containers addObject: [currentContainer copy]];
        [_containersLock unlock];
        
        BOOL writeResult = [[self class] writeContainersPlist: containers toURL: [_storeURL URLByAppendingPathComponent: kContainersPlistFileName]];
            EBAssertOrRecover(writeResult, goto EBFinish);
    }
    
    EBFinish:
    {
        if (startStateResult)
            [self stopState: EBDiskCacheStateUsing];
    }
    
//    #warning debug
//    NSLog(@"### SYNC (FINISH)");
}

- (void)destroy
{
//    #warning debug
//    NSLog(@"### DESTROY");
    
    /* Invalidate ourself. This will block until we're Idle (and therefore don't have any clients), or just acquire
       the lock immediately if we're already Invalid. */
    [_stateLock lockOnConditions: (EBDiskCacheStateIdle | EBDiskCacheStateInvalid)];
    [_stateLock unlockWithCondition: EBDiskCacheStateInvalid];
    
    /* Delete all traces of ourself from disk! */
    [[NSFileManager defaultManager] removeItemAtURL: _storeURL error: nil];
}

#pragma mark - Private Methods -
+ (NSArray *)readContainersPlistFromURL: (NSURL *)containersPlistURL
{
        NSParameterAssert(containersPlistURL);
    
    NSData *containersPlistData = [NSData dataWithContentsOfURL: containersPlistURL];
        EBConfirmOrPerform(containersPlistData, return nil);
    
    /* Unarchive the containers plist and make sure it's an array. */
    NSArray *containers = [NSPropertyListSerialization propertyListWithData: containersPlistData options: NSPropertyListImmutable format: nil error: nil];
        EBAssertOrRecover(containers && [containers isKindOfClass: [NSArray class]], return nil);
    
    return containers;
}

+ (BOOL)writeContainersPlist: (NSArray *)containersPlist toURL: (NSURL *)containersPlistURL
{
        NSParameterAssert(containersPlist);
        NSParameterAssert(containersPlistURL);
    
    NSData *containersPlistData = [NSPropertyListSerialization dataWithPropertyList: containersPlist format: NSPropertyListBinaryFormat_v1_0 options: 0 error: nil];
        EBAssertOrRecover(containersPlistData, return NO);
    
    return [containersPlistData writeToURL: containersPlistURL atomically: YES];
}

- (void)rotate
{
//    #warning debug
//    NSLog(@"### ROTATE");
    
    /* We want to surround this method in in the Using state, so that the receiver is prevented from being invalidated
       until the file-removal process at the end is complete. */
    BOOL startStateResult = [self startState: EBDiskCacheStateUsing];
        EBConfirmOrPerform(startStateResult, return);
    
        /* Once we're in the Using state, we'll continue to the Removing state, which will block until _readingCount == 0.
           (Reading and Removing are mutally-exclusive). */
        startStateResult = [self startState: EBDiskCacheStateRemoving];
            /* We have a grave error if we were invalidated while we were supposed to be in the Using state! */
            EBAssertOrBail(startStateResult);
            
            /* Rotate our in-memory structures by throwing out the oldest one and creating a new, empty one. Also update _firstContainerSize, since it's now 0. */
            NSDictionary *oldContainer = nil;
            NSMutableDictionary *newContainer = [NSMutableDictionary new];
            [_containersLock lockForWriting];
                oldContainer = [_containers lastObject];
                [_containers removeLastObject];
                [_containers insertObject: newContainer atIndex: 0];
                _firstContainerSize = 0;
            [_containersLock unlock];
        
        /* We want to exit the Removing state *before* we start actually removing files, since that could take awhile. This is safe because no
           Readers can start reading while in the Removing state, so that after we swap the data structures (above), it's impossible that
           anyone could have a reference to the URLs that we're about to remove. We want to remain in the Using state though while deleting
           the files, so that the receiver can't be invalidated until we finish. */
        [self stopState: EBDiskCacheStateRemoving];
        
//        #warning debug
//        NSLog(@"START DELETE FILES FOR ROTATE");
        
        /* Go through oldContainer and delete all the files that it references. */
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *currentFileName in [oldContainer objectEnumerator])
        {
//            #warning debug
//            NSLog(@"DELETING FILE FOR ROTATE: %@", currentFileName);
            
            [fileManager removeItemAtURL: [_storeURL URLByAppendingPathComponent: currentFileName] error: nil];
        }
        
//        #warning debug
//        NSLog(@"FINISH DELETE FILES FOR ROTATE");
    
    [self stopState: EBDiskCacheStateUsing];
    
    /* Write our updated plist to disk! */
    [self sync];
}

- (BOOL)startState: (EBDiskCacheState)state
{
        NSParameterAssert(state == EBDiskCacheStateUsing || state == EBDiskCacheStateReading || state == EBDiskCacheStateRemoving);
    
    /* This table maps 'state' to the originating states which permit the lock to be acquired. */
    static const EBDiskCacheState kAcquireLockStates[] =
        {
            [EBDiskCacheStateUsing]     =  EBDiskCacheStateIdle | EBDiskCacheStateUsing | EBDiskCacheStateReading | EBDiskCacheStateRemoving,
            [EBDiskCacheStateReading]   =  EBDiskCacheStateIdle | EBDiskCacheStateUsing | EBDiskCacheStateReading,
            [EBDiskCacheStateRemoving]  =  EBDiskCacheStateIdle | EBDiskCacheStateUsing | EBDiskCacheStateRemoving
        };
    
    BOOL result = NO;
    /* Explicitly allow the Invalid state so that we can return NO without doing anything if we've been invalidated. */
    [_stateLock lockOnConditions: (kAcquireLockStates[state] | EBDiskCacheStateInvalid)];
    
        EBDiskCacheState currentState = [_stateLock condition];
        EBDiskCacheState newState = EBDiskCacheStateInvalid;
        if (currentState != EBDiskCacheStateInvalid)
        {
            if (state == EBDiskCacheStateUsing)
                _usingCount++;
            
            else if (state == EBDiskCacheStateReading)
                _readingCount++;
            
            else if (state == EBDiskCacheStateRemoving)
                _removingCount++;
            
            newState = (_removingCount ? EBDiskCacheStateRemoving : (_readingCount ? EBDiskCacheStateReading : EBDiskCacheStateUsing));
            result = YES;
        }
    
    [_stateLock unlockWithCondition: newState];
    return result;
}

- (void)stopState: (EBDiskCacheState)state
{
        NSParameterAssert(state == EBDiskCacheStateUsing || state == EBDiskCacheStateReading || state == EBDiskCacheStateRemoving);
    
    /* This table maps 'state' to the states that we're allowed to be in when decrementing 'state'. */
    static const EBDiskCacheState kAllowedStates[] =
        {
            [EBDiskCacheStateUsing]     =  EBDiskCacheStateUsing | EBDiskCacheStateReading | EBDiskCacheStateRemoving,
            [EBDiskCacheStateReading]   =  EBDiskCacheStateReading,
            [EBDiskCacheStateRemoving]  =  EBDiskCacheStateRemoving
        };
    
    [_stateLock lock];
    
        EBDiskCacheState currentState = [_stateLock condition];
            /* Verify that 'currentState is valid based on 'state', the state we're decrementing. */
            EBAssertOrBail(kAllowedStates[state] & currentState);
        
        if (state == EBDiskCacheStateUsing)
        {
                EBAssertOrBail(_usingCount);
            _usingCount--;
        }
        
        else if (state == EBDiskCacheStateReading)
        {
                EBAssertOrBail(_readingCount);
            _readingCount--;
        }
        
        else if (state == EBDiskCacheStateRemoving)
        {
                EBAssertOrBail(_removingCount);
            _removingCount--;
        }
        
        EBDiskCacheState newState = (_removingCount ? EBDiskCacheStateRemoving : (_readingCount ? EBDiskCacheStateReading : (_usingCount ? EBDiskCacheStateUsing : EBDiskCacheStateIdle)));
    
    [_stateLock unlockWithCondition: newState];
}

@end