//
//  S3HTTPUrlBuiler.m
//  S3-Objc
//
//  Created by Michael Ledford on 8/10/08.
//  Modernized by Martin Hering on 07/14/12
//  Copyright 2008 Michael Ledford. All rights reserved.
//

#import "S3HTTPUrlBuilder.h"


@implementation S3HTTPURLBuilder

- (id)initWithDelegate:(id)theDelegate
{
    self = [super init];

    if (self != nil) {
        if (theDelegate == nil) {
            return nil;
        }
        [self setDelegate:theDelegate];
    }

    return self;
}

- (id)init
{
    return [self initWithDelegate:nil];
}

- (NSString *)escapedQueryComponentStringWithString:(NSString *)query {
    NSString *escaped = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)query, NULL, (CFStringRef)@"[]#%?/,$+=&@:;()'*!", kCFStringEncodingUTF8));
    return escaped;
}

- (NSString *)encodeQueryStringFromQueryItems:(NSDictionary *)queryItems {
    NSMutableArray *encodedQueries = [NSMutableArray arrayWithCapacity:[queryItems count]];
    NSEnumerator *queryItemsKeyEnumerator = [queryItems keyEnumerator];
    NSString *queryKey;
    while (queryKey = [queryItemsKeyEnumerator nextObject]) {
        if ([[self escapedQueryComponentStringWithString:[queryItems objectForKey:queryKey]] isEqualTo:[NSNull null]]) {
            if ([queryKey isEqualTo:@"acl"] || [queryKey isEqualTo:@"torrent"] || [queryKey isEqualTo:@"location"] || [queryKey isEqualTo:@"logging"]) {
                [encodedQueries insertObject:[self escapedQueryComponentStringWithString:queryKey] atIndex:0];
            } else {
                [encodedQueries addObject:[self escapedQueryComponentStringWithString:queryKey]];                
            }
        } else {
            [encodedQueries addObject:[NSString stringWithFormat:@"%@=%@", [self escapedQueryComponentStringWithString:queryKey], [self escapedQueryComponentStringWithString:[queryItems objectForKey:queryKey]]]];
        }
    }
    
    return [encodedQueries componentsJoinedByString:@"&"];
}

- (NSURL *)url
{
    if ([self delegate] == nil) {
        return nil;
    }

    NSString *protocolScheme = nil;
    if ([[self delegate] respondsToSelector:@selector(httpUrlBuilderWantsProtocolScheme:)]) {
        protocolScheme = [[self delegate] httpUrlBuilderWantsProtocolScheme:self];
    }
    
    NSString *host = nil;
    if ([[self delegate] respondsToSelector:@selector(httpUrlBuilderWantsHost:)]) {
        host = [[self delegate] httpUrlBuilderWantsHost:self];
    }
    
    if ([protocolScheme length] == 0 || [host length] == 0) {
        return nil;
    }

    NSString *key = nil;
    if ([[self delegate] respondsToSelector:@selector(httpUrlBuilderWantsKey:)]) {
        key = [[self delegate] httpUrlBuilderWantsKey:self];
    }
        
    NSString *encodedPath = @"";
    if ([key length] > 0) {
        encodedPath = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)key, NULL, (CFStringRef)@"[]#%?,$+=&@:;()'*!", kCFStringEncodingUTF8));
    }

    NSDictionary *queryItems = nil;
    if ([[self delegate] respondsToSelector:@selector(httpUrlBuilderWantsQueryItems:)]) {
        queryItems = [[self delegate] httpUrlBuilderWantsQueryItems:self];
    }
    
    NSString *encodedQueryString = @"";
    if ([queryItems count] > 0) {
        encodedQueryString = [self encodeQueryStringFromQueryItems:queryItems];        
    }
    
    NSInteger port = 0;
    if ([[self delegate] respondsToSelector:@selector(httpUrlBuilderWantsPort:)]) {
        port = [[self delegate] httpUrlBuilderWantsPort:self];
    }
    
    NSString *portString = @"";
    if ([protocolScheme compare:@"http" options:NSCaseInsensitiveSearch] && (port != 0 && port != 80)) {
        portString = [NSString stringWithFormat:@"%ld", (long)port];
    } else if ([protocolScheme compare:@"https" options:NSCaseInsensitiveSearch] && (port != 0 && port != 443)) {
        portString = [NSString stringWithFormat:@"%ld", (long)port];
    } else {
        portString = [NSString stringWithFormat:@"%ld", (long)port];
    }
    
    NSMutableString *urlString = [NSMutableString string];
    [urlString appendFormat:@"%@://%@", protocolScheme, host];
    if ([portString isEqualTo:@""] == YES) {
        [urlString appendFormat:@":%@", portString];
    }
    [urlString appendString:@"/"];
    if ([encodedPath length] > 0) {
        [urlString appendString:encodedPath];
    }
    if ([encodedQueryString length] > 0) {
        [urlString appendFormat:@"?%@", encodedQueryString];
    }
    
    return [NSURL URLWithString:urlString];
}

@end
