//
//  S3Owner.h
//  S3-Objc
//
//  Created by Olivier Gutknecht on 3/15/06.
//  Modernized by Martin Hering on 07/14/12
//  Copyright 2006 Olivier Gutknecht. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface S3Owner : NSObject
- (id)initWithID:(NSString *)ID displayName:(NSString *)displayName;

@property(readonly, copy) NSString *ID;
@property(readonly, copy) NSString *displayName;

@end
