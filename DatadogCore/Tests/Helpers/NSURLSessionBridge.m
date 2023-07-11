/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import "NSURLSessionBridge.h"

@interface NSURLSessionBridge()
@property NSURLSession *session;
@end

@implementation NSURLSessionBridge

- (id)init:(NSURLSession *)session {
    self = [super init];
    if (self) {
        self.session = session;
    }
    return self;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return [self.session dataTaskWithURL:url completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return [self.session dataTaskWithRequest:request completionHandler:completionHandler];
}

@end
