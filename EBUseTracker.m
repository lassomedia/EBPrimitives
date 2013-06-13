#if __has_feature(objc_arc)
#error ARC required to be disabled (-fno-objc-arc)
#endif

#import "EBUseTracker.h"
#import <EBFoundation/EBFoundation.h>

typedef struct EBUseRecord
{
    struct EBUseRecord *leftRecord;
    struct EBUseRecord *rightRecord;
    id <NSObject> object;
} EBUseRecord;

@interface EBUseEnumerator : NSObject <NSFastEnumeration>
- (id)initWithStartRecord: (EBUseRecord *)startRecord forward: (BOOL)forward mutationIndicator: (unsigned long *)mutationIndicator;
@end

@implementation EBUseTracker
{
    /* The left record of the head record is the tail record */
    EBUseRecord *_headRecord;
    /* Maps object -> EBUseRecord */
    CFMutableDictionaryRef _object2RecordMap;
    /* For NSFastEnumeration */
    unsigned long _mutationIndicator;
}

#pragma mark - Creation -
- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    _object2RecordMap = CFDictionaryCreateMutable(nil, 10, &kCFTypeDictionaryKeyCallBacks, nil);
        EBAssertOrRecover(_object2RecordMap, goto failed);
    
    return self;
    
    failed:
    {
        [self release];
        return nil;
    }
}

- (void)dealloc
{
    /* Free all the records and referenced objects stored in the map */
    for (id <NSObject> currentObject in (NSDictionary *)_object2RecordMap)
    {
        EBUseRecord *record = (EBUseRecord *)CFDictionaryGetValue(_object2RecordMap, currentObject);
            /* Grave error if any record doesn't exist or is nil for the given object. */
            EBAssertOrBail(record);
        
        free(record),
        record = nil;
    }
    
    if (_object2RecordMap)
        CFRelease(_object2RecordMap),
        _object2RecordMap = nil;
    
    [super dealloc];
}

#pragma mark - Methods -
- (void)usedObject: (id <NSObject>)object
{
    [self insertRecordAtHeadForObject: object];
}

- (void)removeObject: (id <NSObject>)object
{
    [self removeRecordForObject: object];
}

- (id <NSObject>)mostRecentlyUsedObject
{
    return (_headRecord ? _headRecord->object : nil);
}

- (id <NSObject>)leastRecentlyUsedObject
{
    return (_headRecord ? _headRecord->leftRecord->object : nil);
}

- (id <NSObject>)popMostRecentlyUsedObject
{
        EBConfirmOrPerform(_headRecord, return nil);
    id <NSObject> object = [[_headRecord->object retain] autorelease];
    [self removeObject: object];
    return object;
}

- (id <NSObject>)popLeastRecentlyUsedObject
{
        EBConfirmOrPerform(_headRecord, return nil);
    id <NSObject> object = [[_headRecord->leftRecord->object retain] autorelease];
    [self removeObject: object];
    return object;
}

- (id <NSFastEnumeration>)mostRecentlyUsedObjectEnumerator
{
    return [[[EBUseEnumerator alloc] initWithStartRecord: _headRecord forward: YES
        mutationIndicator: &_mutationIndicator] autorelease];
}

- (id <NSFastEnumeration>)leastRecentlyUsedObjectEnumerator
{
    return [[[EBUseEnumerator alloc] initWithStartRecord: (_headRecord ? _headRecord->leftRecord : nil) forward: NO
        mutationIndicator: &_mutationIndicator] autorelease];
}

#pragma mark - Private Methods -
/* If a record has neighbors, detaches a record from them. */
static void detachRecord(EBUseRecord *record)
{
        NSCParameterAssert(record);
    
    if (record->leftRecord)
        record->leftRecord->rightRecord = record->rightRecord;
    
    if (record->rightRecord)
        record->rightRecord->leftRecord = record->leftRecord;
}

/* Inserts/moves 'newRecord' to the left of 'neighborRecord', or if 'neighborRecord' == nil, makes 'newRecord' reference itself. */
static void insertRecord(EBUseRecord *neighborRecord, EBUseRecord *newRecord)
{
        NSCParameterAssert(newRecord);
        /* Attempting to move a record before itself has no effect. */
        EBConfirmOrPerform(neighborRecord != newRecord, return);
    
    /* First detach the record */
    detachRecord(newRecord);
    
    /* If we have neighbors: */
    if (neighborRecord)
    {
        /* Update newRecord's fields */
        newRecord->leftRecord = neighborRecord->leftRecord;
        newRecord->rightRecord = neighborRecord;
        /* Update the neighbors' fields */
        newRecord->leftRecord->rightRecord = newRecord;
        newRecord->rightRecord->leftRecord = newRecord;
    }
    
    /* If 'newRecord' is the only record: */
    else
    {
        /* Set newRecord's neighbors to itself */
        newRecord->leftRecord = newRecord;
        newRecord->rightRecord = newRecord;
    }
}

- (void)insertRecordAtHeadForObject: (id <NSObject>)object
{
        NSParameterAssert(object);
    
    /* Get the object's record, creating it if it doesn't exist */
    EBUseRecord *record = (EBUseRecord *)CFDictionaryGetValue(_object2RecordMap, object);
    if (!record)
    {
        /* Using calloc so bytes are zeroed */
        record = calloc(1, sizeof(*record));
            EBAssertOrRecover(record, return);
        
        /* We don't need to retain 'object' because the _object2RecordMap retains it for us! */
        record->object = object;
        /* Store the object-record pair in the map */
        CFDictionarySetValue(_object2RecordMap, object, record);
        /* Update our counter */
        _count++;
    }
    
    /* Insert the record at the head */
    insertRecord(_headRecord, record);
    /* Update _headRecord */
    _headRecord = record;
    
    /* Update our mutation indicator */
    _mutationIndicator++;
}

- (void)removeRecordForObject: (id <NSObject>)object
{
        NSParameterAssert(object);
    
    /* Get the record for the object, and if it doesn't exist, ignore the request to remove the object. */
    EBUseRecord *record = (EBUseRecord *)CFDictionaryGetValue(_object2RecordMap, object);
    
    if (record)
    {
            /* Grave error if we have a record but we have a 0 count! */
            EBAssertOrBail(_count);
        
        /* Doing our cleanup here in the reverse order of -insertObjectAtHead. */
        /* Update _headRecord */
        if (_count == 1) _headRecord = nil;
        else if (_headRecord == record) _headRecord = record->rightRecord;
        /* Detach the record from the linked list */
        detachRecord(record);
        
        /* Update our count */
        _count--;
        /* Remove the object-record pair from the map */
        CFDictionaryRemoveValue(_object2RecordMap, object);
        /* Finally free the record */
        free(record),
        record = nil;
        
        /* Update our mutation indicator */
        _mutationIndicator++;
    }
}

@end

@implementation EBUseEnumerator
{
    EBUseRecord *_startRecord;
    EBUseRecord *_currentRecord;
    BOOL _forward;
    unsigned long *_mutationIndicator;
}

- (id)initWithStartRecord: (EBUseRecord *)startRecord forward: (BOOL)forward mutationIndicator: (unsigned long *)mutationIndicator
{
        /* We don't require a 'startRecord'! If it's nil, we just return 0 objects. */
        NSParameterAssert(mutationIndicator);
    
    if (!(self = [super init]))
        return nil;
    
    _startRecord = startRecord;
    _currentRecord = startRecord;
    _forward = forward;
    _mutationIndicator = mutationIndicator;
    
    return self;
}

- (NSUInteger)countByEnumeratingWithState: (NSFastEnumerationState *)state objects: (id *)requestedObjects count: (NSUInteger)requestedObjectsCount
{
        NSParameterAssert(state);
        NSParameterAssert(requestedObjects || !requestedObjectsCount);
    
    /* Set up 'state' at the beginning of our enumeration */
    if (!state->state)
    {
        state->mutationsPtr = _mutationIndicator;
        state->state = YES;
    }
    
    /* itemsPtr has to be set to where we're putting our objects, which in our case is the supplied stack-based 'requestedObjects' */
    state->itemsPtr = requestedObjects;
    
    NSUInteger returnedObjectsCount = 0;
    for (; _currentRecord && returnedObjectsCount < requestedObjectsCount; returnedObjectsCount++)
    {
        requestedObjects[returnedObjectsCount] = _currentRecord->object;
        
        /* Get the next record, resetting _currentRecord if we've reached the end of our enumeration */
        _currentRecord = (_forward ? _currentRecord->rightRecord : _currentRecord->leftRecord);
        if (_currentRecord == _startRecord)
            _currentRecord = nil;
    }
    
    return returnedObjectsCount;
}

@end