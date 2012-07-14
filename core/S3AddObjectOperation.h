//
//  S3AddObjectOperation.h
//  S3-Objc
//
//  Created by Michael Ledford on 11/26/08.
//  Modernized by Martin Hering on 07/14/12
//  Copyright 2008 Michael Ledford. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "S3Operation.h"

@class S3ConnectionInfo;
@class S3Object;

@interface S3AddObjectOperation : S3Operation {
}

- (id)initWithConnectionInfo:(S3ConnectionInfo *)c object:(S3Object *)o;

@end
