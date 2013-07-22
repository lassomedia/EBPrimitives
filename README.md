EBPrimitives is a framework that includes various generally-useful primitive classes, described below.

## EBConcurrentQueue

EBConcurrentQueue is a lightweight operation queue implementation that supports both concurrency limits and queue priorities. EBConcurrentQueue is implemented as a thin layer atop plain libdispatch queues, eliminating much of the overhead of NSOperationQueue.

## EBConditionLock

EBConditionLock is a locking primitive (similar to NSConditionLock) that allows clients to lock on any one of multiple conditions, specified using a bit field. An EBConditionLock is always in a single condition -- that is, its `condition` property is always an integer with exactly one bit set.

An EBConditionLock's condition is set upon initialization via `-initWithCondition:` (its designated initializer), and when unlocking the lock via `-unlockWithCondition:`.

EBConditionLock is locked by supplying one or more conditions to `-lockOnConditions:`. When more than one condition is supplied, they're combined using a bitwise-OR operation. Calling `-lockOnConditions:` with a value of 0 would result in a deadlock (since no conditions are specified), and therefore raises an exception.

## EBDiskCache

EBDiskCache is a thread-safe, key-value cache implementation that stores and retrieves data to and from disk. Some noteworthy features of EBDiskCache include:

- supports reading and writing data simultaneously from multiple threads
- deletes data from disk when the adjustable size limit is reached
- allows clients to use their own file-reading APIs via the `-startAccessForKey:` method, which returns the URL at which data is stored on disk
- allows clients to safely delete the entire cache from disk

An EBDiskCache instance is created via its designated initializer `-initWithStoreURL:sizeLimit:`, where the on-disk URL for the cache is supplied, along with a maximum size to which the cache is allowed to grow until data is evicted. (The current data-eviction algorithm assumes that entries in the cache are of similar size; if a wide variation exists between the sizes of cache entries, the cache will grow beyond the limit in proportion to the variation. The size limit should therefore be considered a guideline rather than a hard limit.)

EBDiskCache can be destroyed (with all files being removed from disk) via the `-destroy` method. This method safely deletes the cache from disk once there are no outstanding clients reading the cache via `-startAccessForKey:`. Once the cache has been destroyed, `-dataForKey:` and `-startAccessForKey:` return nil for all keys, and other methods (such as `-setData:forKey:` and `-sync`) do nothing.

## EBReadWriteLock

EBReadWriteLock is a simple Objective-C read-write lock, wrapping pthread's rwlock implementation.

## EBUseTracker

EBUseTracker is an Objective-C least-recently-used (LRU) and most-recently-used (MRU) implementation that supports both forward and reverse enumeration.

## Requirements

- Mac OS 10.8 or iOS 6. (Earlier platforms have not been tested.)

## Integration

1. Integrate [EBFoundation](https://github.com/davekeck/EBFoundation) into your project.
2. Drag EBPrimitives.xcodeproj into your project's file hierarchy.
3. In your target's "Build Phases" tab:
    * Add EBPrimitives as a dependency ("Target Dependencies" section)
    * Link against libEBPrimitives.a ("Link Binary With Libraries" section)
4. Add `#import <EBPrimitives/EBPrimitives.h>` to your source files.

## Credits

EBPrimitives was created for [Lasso](http://las.so).

## License

EBPrimitives is available under the MIT license; see the LICENSE file for more information.