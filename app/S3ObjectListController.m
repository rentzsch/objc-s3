//
//  S3ObjectListController.m
//  S3-Objc
//
//  Created by Olivier Gutknecht on 4/3/06.
//  Copyright 2006 Olivier Gutknecht. All rights reserved.
//

#import <SystemConfiguration/SystemConfiguration.h>

#import "S3ObjectListController.h"
#import "S3Extensions.h"
#import "S3Connection.h"
#import "S3Bucket.h"
#import "S3ObjectOperations.h"
#import "S3Application.h"
#import "S3ObjectDownloadOperation.h"
#import "S3ObjectUploadOperation.h"

#define SHEET_CANCEL 0
#define SHEET_OK 1

// These keys are also used in nib file, for bindings

#define ACL_PRIVATE @"private"

#define FILEDATA_PATH @"path"
#define FILEDATA_KEY  @"key"
#define FILEDATA_TYPE @"mime"
#define FILEDATA_SIZE @"size"

@implementation S3ObjectListController

#pragma mark - 
#pragma mark Toolbar management

-(void)awakeFromNib
{
	NSToolbar* toolbar = [[[NSToolbar alloc] initWithIdentifier:@"ObjectsToolbar"] autorelease];
	[toolbar setDelegate:self];
	[toolbar setVisible:YES];
	[toolbar setAllowsUserCustomization:YES];
	[toolbar setAutosavesConfiguration:NO];
	[toolbar setSizeMode:NSToolbarSizeModeDefault];
	[toolbar setDisplayMode:NSToolbarDisplayModeDefault];
	[[self window] setToolbar:toolbar];
	[_objectsController setFileOperationsDelegate:self];
}

- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects: NSToolbarSeparatorItemIdentifier,
		NSToolbarSpaceItemIdentifier,
		NSToolbarFlexibleSpaceItemIdentifier,
		@"Refresh", @"Upload", @"Download", @"Remove", @"Remove All",nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
	if ([[theItem itemIdentifier] isEqualToString: @"Remove All"])
        return [[_objectsController arrangedObjects] count] > 0;
    if ([[theItem itemIdentifier] isEqualToString: @"Remove"])
		return [_objectsController canRemove];
	if ([[theItem itemIdentifier] isEqualToString: @"Download"])
		return [_objectsController canRemove];
	return YES;
}

- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
	return [NSArray arrayWithObjects: @"Upload", @"Download", @"Remove", NSToolbarSeparatorItemIdentifier,  @"Remove All", NSToolbarFlexibleSpaceItemIdentifier, @"Refresh", nil]; 
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSString*)itemIdentifier willBeInsertedIntoToolbar:(BOOL) flag
{
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier];
	
	if ([itemIdentifier isEqualToString: @"Upload"])
	{
		[item setLabel: NSLocalizedString(@"Upload", nil)];
		[item setPaletteLabel: [item label]];
		[item setImage: [NSImage imageNamed: @"upload.icns"]];
		[item setTarget:self];
		[item setAction:@selector(upload:)];
    }
	if ([itemIdentifier isEqualToString: @"Download"])
	{
		[item setLabel: NSLocalizedString(@"Download", nil)];
		[item setPaletteLabel: [item label]];
		[item setImage: [NSImage imageNamed: @"download.icns"]];
		[item setTarget:self];
		[item setAction:@selector(download:)];
    }
	else if ([itemIdentifier isEqualToString: @"Remove"])
	{
		[item setLabel: NSLocalizedString(@"Remove", nil)];
		[item setPaletteLabel: [item label]];
		[item setImage: [NSImage imageNamed: @"delete.icns"]];
		[item setTarget:self];
		[item setAction:@selector(remove:)];
    }
	else if ([itemIdentifier isEqualToString: @"Remove All"])
	{
		[item setLabel: NSLocalizedString(@"Remove All", nil)];
		[item setPaletteLabel: [item label]];
		[item setImage: [NSImage imageNamed: @"delete.icns"]];
		[item setTarget:self];
		[item setAction:@selector(removeAll:)];
    }
	else if ([itemIdentifier isEqualToString: @"Refresh"])
	{
		[item setLabel: NSLocalizedString(@"Refresh", nil)];
		[item setPaletteLabel: [item label]];
		[item setImage: [NSImage imageNamed: @"refresh.icns"]];
		[item setTarget:self];
		[item setAction:@selector(refresh:)];
    }
	
    return [item autorelease];
}


#pragma mark - 
#pragma mark Misc Delegates


-(void)windowDidLoad
{
	[self refresh:self];
}

- (IBAction)cancelSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:SHEET_CANCEL];
}

- (IBAction)closeSheet:(id)sender
{
	[NSApp endSheet:[sender window] returnCode:SHEET_OK];
}

-(void)didPresentErrorWithRecovery:(BOOL)didRecover contextInfo:(void *)contextInfo
{
}

-(void)operationStateChange:(S3Operation*)o;
{
}

-(void)operationDidFail:(S3Operation*)o
{
	[[self window] presentError:[o error] modalForWindow:[self window] delegate:self didPresentSelector:@selector(didPresentErrorWithRecovery:contextInfo:) contextInfo:nil];
}

-(void)operationDidFinish:(S3Operation*)op
{
	BOOL b = [op operationSuccess];
	if (!b)	{	
		[self operationDidFail:op];
		return;
	}
	
#ifdef S3_DOWNLOADS_NSURLCONNECTION
	if ([op isKindOfClass:[S3ObjectDownloadOperation class]]) {
		NSData* d = [(S3ObjectDownloadOperation*)op data];
		NSSavePanel* sp = [NSSavePanel savePanel];
		int runResult;
		NSString* n = [[(S3ObjectDownloadOperation*)op object] key];
		if (n==nil) n = @"Untitled";
		runResult = [sp runModalForDirectory:nil file:n];
		
		if (runResult == NSOKButton) {
			if (![d writeToFile:[sp filename] atomically:YES])
				NSBeep();
		}
	}
#endif
	if ([op isKindOfClass:[S3ObjectListOperation class]]) {
		[self setObjects:[(S3ObjectListOperation*)op objects]];
		[self setObjectsInfo:[(S3ObjectListOperation*)op metadata]];
	}
	if ([op isKindOfClass:[S3ObjectUploadOperation class]]||[op isKindOfClass:[S3ObjectStreamedUploadOperation class]]||[op isKindOfClass:[S3ObjectDeleteOperation class]])
		[self refresh:self];
}

#pragma mark -
#pragma mark Actions

-(IBAction)refresh:(id)sender
{
	S3ObjectListOperation* op = [S3ObjectListOperation objectListWithConnection:_connection delegate:self bucket:_bucket];
	[(S3Application*)NSApp logOperation:op];
	[self setCurrentOperations:[NSMutableSet setWithObject:op]];
}

-(IBAction)removeAll:(id)sender
{
    NSAlert * alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Remove all objects permanently?",nil)];
    [alert setInformativeText:NSLocalizedString(@"Warning: Are you sure you want to remove all objects in this bucket? This operation cannot be undone.",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel",nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Remove",nil)];
    if ([alert runModal] == NSAlertFirstButtonReturn)
    {   
        [alert release];
        return;
    }
    [alert release];
    
	NSMutableSet* ops = [NSMutableSet set];
	S3Object* b;
	NSEnumerator* e = [[_objectsController arrangedObjects] objectEnumerator];
	while (b = [e nextObject])
	{
		S3ObjectDeleteOperation* op = [S3ObjectDeleteOperation objectDeletionWithConnection:_connection delegate:self bucket:_bucket object:b];
		[(S3Application*)NSApp logOperation:op];
		[ops addObject:op];
	}
	[self setCurrentOperations:ops];
}

-(IBAction)remove:(id)sender
{
	NSMutableSet* ops = [NSMutableSet set];
	S3Object* b;
	NSEnumerator* e = [[_objectsController selectedObjects] objectEnumerator];
	while (b = [e nextObject])
	{
		S3ObjectDeleteOperation* op = [S3ObjectDeleteOperation objectDeletionWithConnection:_connection delegate:self bucket:_bucket object:b];
		[(S3Application*)NSApp logOperation:op];
		[ops addObject:op];
	}
	[self setCurrentOperations:ops];
}

-(IBAction)download:(id)sender
{
	NSMutableSet* ops = [NSMutableSet set];
	S3Object* b;
	NSEnumerator* e = [[_objectsController selectedObjects] objectEnumerator];
	while (b = [e nextObject])
	{
#ifdef S3_DOWNLOADS_NSURLCONNECTION
		S3ObjectDownloadOperation* op = [S3ObjectDownloadOperation objectDownloadWithConnection:_connection delegate:self bucket:_bucket object:b];
		[(S3Application*)NSApp logOperation:op];
		[ops addObject:op];
#else
		NSSavePanel* sp = [NSSavePanel savePanel];
		int runResult;
		NSString* n = [b key];
		if (n==nil) n = @"Untitled";
		runResult = [sp runModalForDirectory:nil file:n];
		if (runResult == NSOKButton) {
			S3ObjectDownloadOperation* op = [S3ObjectDownloadOperation objectDownloadWithConnection:_connection delegate:self bucket:_bucket object:b toPath:[sp filename]];
			[(S3Application*)NSApp logOperation:op];
			[ops addObject:op];
		}
#endif
	}
	[self setCurrentOperations:ops];
}


-(void)uploadFile:(NSString*)path key:(NSString*)key acl:(NSString*)acl mimeType:(NSString*)mimetype
{
	if (![self acceptFileForImport:path])
		return;	
	
    S3Operation* op;
    
    CFDictionaryRef proxyDict = SCDynamicStoreCopyProxies(NULL); 
    BOOL hasProxy = (CFDictionaryGetValue(proxyDict, kSCPropNetProxiesHTTPProxy) != NULL);
    CFRelease(proxyDict);
	
    if (hasProxy || TRUE)
    {
        NSData* data = [NSData dataWithContentsOfFile:path];
        op = [S3ObjectUploadOperation objectUploadWithConnection:_connection delegate:self bucket:_bucket key:key data:data acl:acl mimeType:mimetype];
    }
    else 
        op = [S3ObjectStreamedUploadOperation objectUploadWithConnection:_connection delegate:self bucket:_bucket key:key path:path acl:acl mimeType:mimetype];
    
    [(S3Application*)NSApp logOperation:op];
    [self setCurrentOperations:[NSMutableSet setWithObject:op]];    
}

-(void)uploadFiles
{	
	NSEnumerator* e = [[self uploadData] objectEnumerator];
	NSDictionary* data;

	while (data = [e nextObject])
		[self uploadFile:[data objectForKey:FILEDATA_PATH] key:[data objectForKey:FILEDATA_KEY] acl:[self uploadACL] mimeType:[data objectForKey:FILEDATA_TYPE]];		
}


-(IBAction)upload:(id)sender
{
	NSOpenPanel *oPanel = [[NSOpenPanel openPanel] retain];
	[oPanel setAllowsMultipleSelection:YES];
	[oPanel setPrompt:NSLocalizedString(@"Upload",nil)];
	[oPanel setCanChooseDirectories:TRUE];
	[oPanel beginForDirectory:nil file:nil types:nil modelessDelegate:self didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
	if (returnCode!=SHEET_OK)
		return;
	
	[self uploadFiles];
}

-(BOOL)acceptFileForImport:(NSString*)path
{
	return [[NSFileManager defaultManager] isReadableFileAtPath:path];
}

-(void)importFiles:(NSArray*)files withDialog:(BOOL)dialog
{
	// First expand directories and only keep paths to files
	NSArray* paths = [files expandPaths];
		
	NSString* path;
	NSEnumerator* e = [paths objectEnumerator];
	NSMutableArray* filesInfo = [NSMutableArray array];
	NSString* prefix = [NSString commonPathComponentInPaths:paths]; 
	
	while (path = [e nextObject])
	{
		NSMutableDictionary* info = [NSMutableDictionary dictionary];
		[info setObject:path forKey:FILEDATA_PATH];
		[info setObject:[path readableSizeForPath] forKey:FILEDATA_SIZE];
		[info safeSetObject:[path mimeTypeForPath] forKey:FILEDATA_TYPE withValueForNil:@""];
		[info setObject:[path substringFromIndex:[prefix length]] forKey:FILEDATA_KEY];
		[filesInfo addObject:info];
	}
	
	[self setUploadData:filesInfo];
	[self setUploadACL:ACL_PRIVATE];
	[self setUploadSize:[NSString readableSizeForPaths:paths]];

	if (!dialog)
		[self uploadFiles];
	else
	{
		if ([paths count]==1)
		{
			[self setUploadFilename:[[paths objectAtIndex:0] stringByAbbreviatingWithTildeInPath]];
			[NSApp beginSheet:uploadSheet modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];			
		}
		else
		{
			[self setUploadFilename:[NSString stringWithFormat:NSLocalizedString(@"%d elements in %@",nil),[paths count],[prefix stringByAbbreviatingWithTildeInPath]]];
			[NSApp beginSheet:multipleUploadSheet modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];							
		}
	}
}


- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	NSArray *files = [panel filenames];
	
	if (returnCode != NSOKButton) {
		[panel release];
		return;
	}
	[panel release];

	[self importFiles:files withDialog:TRUE];
}

#pragma mark -
#pragma mark Key-value coding

- (NSMutableArray *)objects
{
    return _objects; 
}
- (void)setObjects:(NSMutableArray *)aObjects
{
    [_objects release];
    _objects = [aObjects retain];
}


- (NSMutableDictionary *)objectsInfo
{
    return _objectsInfo; 
}
- (void)setObjectsInfo:(NSMutableDictionary *)aObjectsInfo
{
    [_objectsInfo release];
    _objectsInfo = [aObjectsInfo retain];
}


- (S3Bucket *)bucket
{
    return _bucket; 
}
- (void)setBucket:(S3Bucket *)aBucket
{
    [_bucket release];
    _bucket = [aBucket retain];
}

- (S3Connection *)connection
{
    return _connection; 
}
- (void)setConnection:(S3Connection *)aConnection
{
    [_connection release];
    _connection = [aConnection retain];
}

- (NSMutableSet *)currentOperations
{
    return _currentOperations; 
}
- (void)setCurrentOperations:(NSMutableSet *)aCurrentOperations
{
    [_currentOperations release];
    _currentOperations = [aCurrentOperations retain];
}

- (NSString *)uploadACL
{
    return _uploadACL; 
}
- (void)setUploadACL:(NSString *)anUploadACL
{
    [_uploadACL release];
    _uploadACL = [anUploadACL retain];
}

- (NSString *)uploadFilename
{
    return _uploadFilename; 
}
- (void)setUploadFilename:(NSString *)anUploadFilename
{
    [_uploadFilename release];
    _uploadFilename = [anUploadFilename retain];
}

- (NSString *)uploadSize
{
    return _uploadSize; 
}
- (void)setUploadSize:(NSString *)anUploadSize
{
    [_uploadSize release];
    _uploadSize = [anUploadSize retain];
}

- (NSMutableArray *)uploadData
{
    return [[_uploadData retain] autorelease]; 
}
- (void)setUploadData:(NSMutableArray *)data
{
    [_uploadData release];
    _uploadData = [data retain];
}

#pragma mark -
#pragma mark Dealloc

-(void)dealloc
{
	[self setObjects:nil];
	[self setObjectsInfo:nil];
	[self setBucket:nil];

	[self setConnection:nil];
	[self setCurrentOperations:nil];

	[self setUploadACL:nil];
	[self setUploadFilename:nil];
	[self setUploadData:nil];

	[self setCurrentOperations:nil];
	
	[super dealloc];
}

@end