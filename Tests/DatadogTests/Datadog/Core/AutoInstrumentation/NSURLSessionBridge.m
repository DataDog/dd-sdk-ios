/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "NSURLSessionBridge.h"

@implementation NSURLSessionBridge

+ (NSURLSessionDataTask *)session:(NSURLSession *)session dataTaskWithURL:(NSURL *)url completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return [session dataTaskWithURL:url completionHandler:completionHandler];
}

+ (NSURLSessionDataTask *)session:(NSURLSession *)session dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return [session dataTaskWithRequest:request completionHandler:completionHandler];
}

@end
