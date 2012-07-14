//
//  S3ListObjectOperation.h
//  S3-Objc
//
//  Created by Michael Ledford on 11/19/08.
//  Modernized by Martin Hering on 07/14/12
//  Copyright 2008 Michael Ledford. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "S3Operation.h"

@interface S3ListObjectOperation : S3Operation {
}

- (id)initWithConnectionInfo:(S3ConnectionInfo *)theConnectionInfo bucket:(S3Bucket *)bucket marker:(NSString *)marker;
- (id)initWithConnectionInfo:(S3ConnectionInfo *)theConnectionInfo bucket:(S3Bucket *)bucket;

- (NSArray *)objects;
- (NSMutableDictionary *)metadata;
- (S3ListObjectOperation *)operationForNextChunk;

@end
