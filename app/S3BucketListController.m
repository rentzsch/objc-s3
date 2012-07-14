//
//  S3BucketListController.m
//  S3-Objc
//
//  Created by Olivier Gutknecht on 4/3/06.
//  Copyright 2006 Olivier Gutknecht. All rights reserved.
//

#import "S3BucketListController.h"
#import "AWSRegion.h"
#import "S3Owner.h"
#import "S3Bucket.h"
#import "S3Extensions.h"
#import "S3ObjectListController.h"
#import "S3ApplicationDelegate.h"
#import "S3ListBucketOperation.h"
#import "S3AddBucketOperation.h"
#import "S3DeleteBucketOperation.h"
#import "S3OperationQueue.h"

#define SHEET_CANCEL 0
#define SHEET_OK 1

enum {
    USStandardLocation = 0,
    USWestLocation = 1,
    EUIrelandLocation = 2
};


@interface S3BucketListController () <NSToolbarDelegate>

@end

@implementation S3BucketListController

#pragma mark -
#pragma mark Toolbar management

- (void)awakeFromNib
{
    if ([S3ActiveWindowController instancesRespondToSelector:@selector(awakeFromNib)] == YES) {
        [super awakeFromNib];
    }
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"BucketsToolbar"];
    [toolbar setDelegate:self];
    [toolbar setVisible:YES];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:NO];
    [toolbar setSizeMode:NSToolbarSizeModeDefault];
    [toolbar setDisplayMode:NSToolbarDisplayModeDefault];
    [[self window] setToolbar:toolbar];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeZone:[NSTimeZone defaultTimeZone]];
    [[[[[[self window] contentView] viewWithTag:10] tableColumnWithIdentifier:@"creationDate"] dataCell] setFormatter:dateFormatter];

    _bucketListControllerCache = [[NSMutableDictionary alloc] init];

    [[[NSApp delegate] queue] addQueueListener:self];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return @[NSToolbarSeparatorItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        NSToolbarFlexibleSpaceItemIdentifier,
        @"Refresh", @"Remove", @"Add"];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    if ([[theItem itemIdentifier] isEqualToString: @"Remove"])
        return [_bucketsController canRemove];
    return YES;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return @[@"Add", @"Remove", NSToolbarFlexibleSpaceItemIdentifier, @"Refresh"]; 
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier];
    
    if ([itemIdentifier isEqualToString: @"Add"])
    {
        [item setLabel: NSLocalizedString(@"Add", nil)];
        [item setPaletteLabel: [item label]];
        [item setImage: [NSImage imageNamed: @"add.icns"]];
        [item setTarget:self];
        [item setAction:@selector(add:)];
    }
    else if ([itemIdentifier isEqualToString: @"Remove"])
    {
        [item setLabel: NSLocalizedString(@"Remove", nil)];
        [item setPaletteLabel: [item label]];
        [item setImage: [NSImage imageNamed: @"delete.icns"]];
        [item setTarget:self];
        [item setAction:@selector(remove:)];
    }
    else if ([itemIdentifier isEqualToString: @"Refresh"])
    {
        [item setLabel: NSLocalizedString(@"Refresh", nil)];
        [item setPaletteLabel: [item label]];
        [item setImage: [NSImage imageNamed: @"refresh.icns"]];
        [item setTarget:self];
        [item setAction:@selector(refresh:)];
    }
    
    return item;
}

#pragma mark -
#pragma mark Misc Delegates

- (IBAction)cancelSheet:(id)sender
{
    [NSApp endSheet:addSheet returnCode:SHEET_CANCEL];
}

- (IBAction)closeSheet:(id)sender
{
    [NSApp endSheet:addSheet returnCode:SHEET_OK];
}

- (void)operationQueueOperationStateDidChange:(NSNotification *)notification
{
    S3Operation *operation = [[notification userInfo] objectForKey:S3OperationObjectKey];
    NSUInteger index = [_operations indexOfObjectIdenticalTo:operation];
    if (index == NSNotFound) {
        return;
    }
    
    [super operationQueueOperationStateDidChange:notification];

    if ([operation state] == S3OperationDone) {
        if ([operation isKindOfClass:[S3ListBucketOperation class]]) {
            [self setBuckets:[(S3ListBucketOperation *)operation bucketList]];
            [self setBucketsOwner:[(S3ListBucketOperation *)operation owner]];			
        } else {
            [self refresh:self];            
        }
    }
}

#pragma mark -
#pragma mark Actions

- (IBAction)remove:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    if ([[_bucketsController selectedObjects] count] == 1) {
        [alert setMessageText:NSLocalizedString(@"Remove bucket permanently?",nil)];
        [alert setInformativeText:NSLocalizedString(@"Warning: Are you sure you want to remove the bucket? This operation cannot be undone.",nil)];        
    } else {
        [alert setMessageText:NSLocalizedString(@"Remove all selected buckets permanently?",nil)];
        [alert setInformativeText:NSLocalizedString(@"Warning: Are you sure you want to remove all the selected buckets? This operation cannot be undone.",nil)];
    }
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Remove",nil)];
    if ([alert runModal] == NSAlertFirstButtonReturn)
    {   
        return;
    }

    S3Bucket *b;
    NSEnumerator *e = [[_bucketsController selectedObjects] objectEnumerator];
    
    while (b = [e nextObject]) {
        S3DeleteBucketOperation *op = [[S3DeleteBucketOperation alloc] initWithConnectionInfo:[self connectionInfo] bucket:b];
        [self addToCurrentOperations:op];
    }
}

- (IBAction)refresh:(id)sender
{
	S3ListBucketOperation *op = [[S3ListBucketOperation alloc] initWithConnectionInfo:[self connectionInfo]];
    
    [self addToCurrentOperations:op];
}


- (void)didEndSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
    if (returnCode==SHEET_OK) {
        S3Bucket *newBucket = [[S3Bucket alloc] initWithName:_name];
        if (newBucket == nil) {
            return;
        }
        
        AWSRegion *bucketRegion = nil;
        if (_location == USWestLocation) {
            bucketRegion = [AWSRegion regionWithKey:AWSRegionUSWestKey];
        } else if (_location == EUIrelandLocation) {
            bucketRegion = [AWSRegion regionWithKey:AWSRegionEUIrelandKey];
        } else {
            bucketRegion = [AWSRegion regionWithKey:AWSRegionUSStandardKey];
        }
                
        S3AddBucketOperation *op = [[S3AddBucketOperation alloc] initWithConnectionInfo:[self connectionInfo] bucket:newBucket region:bucketRegion];
        
        [self addToCurrentOperations:op];
    }
}

- (IBAction)add:(id)sender
{
    [self setName:@"Untitled"];
    [NSApp beginSheet:addSheet modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)open:(id)sender
{
    
    S3Bucket *b;
    NSEnumerator* e = [[_bucketsController selectedObjects] objectEnumerator];
    while (b = [e nextObject])
    {
        S3ObjectListController *c = nil;
        if ((c = [_bucketListControllerCache objectForKey:b])) {
            [c showWindow:self];
        } else {
            c = [[S3ObjectListController alloc] initWithWindowNibName:@"Objects"];
            [c setBucket:b];

            [c setConnectionInfo:[self connectionInfo]];
            
            [c showWindow:self];            
            [_bucketListControllerCache setObject:c forKey:b];
        }
    }
}

#pragma mark -
#pragma mark Key-value coding

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    if ([key isEqual:@"isValidName"]) {
        return [NSSet setWithObject:@"name"];
    }
    
    return nil;
}

- (NSString *)name
{
    return _name; 
}

- (void)setName:(NSString *)aName
{
    _name = aName;
}

- (BOOL)isValidName
{
    // The length of the bucket name must be between 3 and 255 bytes. It can contain letters, numbers, dashes, and underscores.
    if ([_name length]<3)
        return NO;
    if ([_name length]>255)
        return NO;
    // This is a bit brute force, we should check iteratively and not reinstantiate on every call.
    NSCharacterSet *s = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-."] invertedSet];
    if ([_name rangeOfCharacterFromSet:s].location!=NSNotFound)
        return NO;
    return YES;
}

- (S3Owner *)bucketsOwner
{
    return _bucketsOwner; 
}

- (void)setBucketsOwner:(S3Owner *)anBucketsOwner
{
    _bucketsOwner = anBucketsOwner;
}

- (NSArray *)buckets
{
    return _buckets; 
}

- (void)setBuckets:(NSArray *)aBuckets
{
    _buckets = aBuckets;
}

#pragma mark -
#pragma mark Dealloc

-(void)dealloc
{
    [[[NSApp delegate] queue] removeQueueListener:self];
}

@end
