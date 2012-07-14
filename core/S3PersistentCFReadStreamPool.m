//
//  S3PersistentCFReadStreamPool.m
//  S3-Objc
//
//  Created by Michael Ledford on 7/29/08.
//  Modernized by Martin Hering on 07/14/12
//  Copyright 2008 Michael Ledford. All rights reserved.
//

#import "S3PersistentCFReadStreamPool.h"

#import <sys/socket.h>

CFStringRef S3PersistentCFReadStreamPoolUniquePeropertyKey = CFSTR("UniqueProperty");

static S3PersistentCFReadStreamPool *_sharedS3PersistentCFReadStreamPoolInstance;

static NSInteger S3TimeBetweenCleanings = 20;
static NSString *S3PersistentReadStreamKey = @"S3PersistentReadStreamKey";
static NSString *S3DateKey = @"S3DateKey";

@interface S3PersistentCFReadStreamPool ()
- (void)nukePool;
- (void)disarmCleanPoolTimer;
@end

@implementation S3PersistentCFReadStreamPool {
    NSMutableDictionary *_activePersistentReadStreams;
    NSMutableArray *_overflow;
    NSTimer *_cleanPoolTimer;
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _activePersistentReadStreams = [[NSMutableDictionary alloc] init];
        _overflow = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [self disarmCleanPoolTimer];
    [self nukePool];
}

+ (S3PersistentCFReadStreamPool *)sharedPersistentCFReadStreamPool
{
    if (_sharedS3PersistentCFReadStreamPoolInstance == nil) {
        _sharedS3PersistentCFReadStreamPoolInstance = [[S3PersistentCFReadStreamPool alloc] init];
    }
    return _sharedS3PersistentCFReadStreamPoolInstance;
}

+ (BOOL)sharedPersistentCFReadStreamPoolExists
{
    if (_sharedS3PersistentCFReadStreamPoolInstance == nil) {
        return NO;
    }
    return YES;
}

- (void)armCleanPoolTimer
{
    if (_cleanPoolTimer == nil) {
        _cleanPoolTimer = [NSTimer scheduledTimerWithTimeInterval:S3TimeBetweenCleanings target:self selector:@selector(cleanPool:) userInfo:nil repeats:NO];        
    }
}

-(void)disarmCleanPoolTimer
{
	[_cleanPoolTimer invalidate];
	_cleanPoolTimer = nil;	
}

- (BOOL)addOpenedPersistentCFReadStream:(CFReadStreamRef)persistentCFReadStream inQueuePosition:(NSUInteger)position
{
    if (persistentCFReadStream == nil) {
        return NO;
    }
    
    CFStreamStatus streamStatus = CFReadStreamGetStatus(persistentCFReadStream);
    if (streamStatus == kCFStreamStatusNotOpen || streamStatus == kCFStreamStatusAtEnd || 
        streamStatus == kCFStreamStatusClosed || streamStatus == kCFStreamStatusError) {
        return NO;
    }

    NSNumber *positionNumber = @(position);
    NSDictionary *foundDictionary = [_activePersistentReadStreams objectForKey:positionNumber];
    CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
    if (foundReadStream != nil) {
        streamStatus = CFReadStreamGetStatus(foundReadStream);
        if (streamStatus == kCFStreamStatusNotOpen || streamStatus == kCFStreamStatusAtEnd || 
            streamStatus == kCFStreamStatusClosed || streamStatus == kCFStreamStatusError) {
            CFReadStreamClose(foundReadStream);
            NSDate *currentTime = [[NSDate alloc] init];
            NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:(__bridge NSInputStream *)persistentCFReadStream, S3PersistentReadStreamKey, currentTime, S3DateKey, nil];
            [_activePersistentReadStreams setObject:dictionary forKey:positionNumber];
        } else {
            while ((streamStatus == kCFStreamStatusOpening || streamStatus == kCFStreamStatusOpen || 
                    streamStatus == kCFStreamStatusReading || streamStatus == kCFStreamStatusWriting) && ((++position) < NSUIntegerMax)) {
                positionNumber = @(position);
                foundDictionary = [_activePersistentReadStreams objectForKey:positionNumber];
                foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
                if (foundReadStream != nil) {
                    streamStatus = CFReadStreamGetStatus(foundReadStream);                    
                } else {
                    break;
                }
            }
            if (position == NSUIntegerMax) {
                [_overflow addObject:(__bridge NSInputStream *)persistentCFReadStream];
            } else {
                if (foundReadStream != nil &&
                    (streamStatus == kCFStreamStatusNotOpen || streamStatus == kCFStreamStatusAtEnd || 
                     streamStatus == kCFStreamStatusClosed || streamStatus == kCFStreamStatusError)) {
                    CFReadStreamClose(foundReadStream);
                }
                NSDate *currentTime = [[NSDate alloc] init];
                NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:(__bridge NSInputStream *)persistentCFReadStream, S3PersistentReadStreamKey, currentTime, S3DateKey, nil];
                [_activePersistentReadStreams setObject:dictionary forKey:positionNumber];
            }
        }        
    } else {
        NSDate *currentTime = [[NSDate alloc] init];
        NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:(__bridge NSInputStream *)persistentCFReadStream, S3PersistentReadStreamKey, currentTime, S3DateKey, nil];
        [_activePersistentReadStreams setObject:dictionary forKey:positionNumber];
    }
    
    // Enable timer firing mechanisim here for cleaning up dead streams.
    [self armCleanPoolTimer];
    
    return YES;
}

- (BOOL)addOpenedPersistentCFReadStream:(CFReadStreamRef)persistentCFReadStream
{
    return [self addOpenedPersistentCFReadStream:persistentCFReadStream inQueuePosition:0];
}

- (void)cleanPool:(NSTimer *)timer
{
    NSLog(@"cleanPool:");
    NSEnumerator *objectEnumerator = [_activePersistentReadStreams objectEnumerator];
    NSDictionary *foundDictionary = nil;
    NSMutableArray *keysToRemove = [[NSMutableArray alloc] init];
    while (foundDictionary = [objectEnumerator nextObject]) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        CFStreamStatus streamStatus = CFReadStreamGetStatus(foundReadStream);
        if (streamStatus == kCFStreamStatusNotOpen || streamStatus == kCFStreamStatusAtEnd || 
            streamStatus == kCFStreamStatusClosed || streamStatus == kCFStreamStatusError) {
            NSDate *currentTime = [[NSDate alloc] init];
            if ([currentTime timeIntervalSinceDate:[foundDictionary objectForKey:S3DateKey]] > S3TimeBetweenCleanings) {
                NSArray *keys = [_activePersistentReadStreams allKeysForObject:foundDictionary];
                [keysToRemove addObjectsFromArray:keys];
                CFReadStreamClose(foundReadStream);
            }
        }
    }
    [_activePersistentReadStreams removeObjectsForKeys:keysToRemove];
    [keysToRemove removeAllObjects];
    
    for (foundDictionary in _overflow) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        CFStreamStatus streamStatus = CFReadStreamGetStatus(foundReadStream);
        if (streamStatus == kCFStreamStatusNotOpen || streamStatus == kCFStreamStatusAtEnd || 
            streamStatus == kCFStreamStatusClosed || streamStatus == kCFStreamStatusError) {
            NSDate *currentTime = [[NSDate alloc] init];
            if ([currentTime timeIntervalSinceDate:[foundDictionary objectForKey:S3DateKey]] > S3TimeBetweenCleanings) {
                [keysToRemove addObject:foundDictionary];
                CFReadStreamClose(foundReadStream);                
            }
        }
    }
    [_overflow removeObjectsInArray:keysToRemove];
    keysToRemove = nil;
    
    [self disarmCleanPoolTimer];
        
    // If there are still kids in the  pool
    // arm another pool boy to come clean up.
    if ([_activePersistentReadStreams count] > 0 || [_overflow count] > 0) {
        [self armCleanPoolTimer];
    }
}

- (void)removeOpenedPersistentCFReadStream:(CFReadStreamRef)readStream
{
    NSEnumerator *objectEnumerator = [_activePersistentReadStreams objectEnumerator];
    NSDictionary *foundDictionary = nil;
    NSMutableArray *keysToRemove = [[NSMutableArray alloc] init];
    while (foundDictionary = [objectEnumerator nextObject]) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        if (foundReadStream == readStream) {
            NSArray *keys = [_activePersistentReadStreams allKeysForObject:foundDictionary];
            [keysToRemove addObjectsFromArray:keys];
            CFReadStreamClose(foundReadStream);
        }
    }
    [_activePersistentReadStreams removeObjectsForKeys:keysToRemove];
    [keysToRemove removeAllObjects];

    for (foundDictionary in _overflow) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        if (foundReadStream == readStream) {
            [keysToRemove addObject:foundDictionary];
            CFReadStreamClose(foundReadStream);
        }
    }
    [_overflow removeObjectsInArray:keysToRemove];
    keysToRemove = nil;    
}

- (void)nukePool
{
    NSEnumerator *objectEnumerator = [_activePersistentReadStreams objectEnumerator];
    NSDictionary *foundDictionary = nil;
    while (foundDictionary = [objectEnumerator nextObject]) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        CFReadStreamClose(foundReadStream);
    }
    for (foundDictionary in _overflow) {
        CFReadStreamRef foundReadStream = (__bridge CFReadStreamRef)[foundDictionary objectForKey:S3PersistentReadStreamKey];
        CFReadStreamClose(foundReadStream);                
    }
}

@end
