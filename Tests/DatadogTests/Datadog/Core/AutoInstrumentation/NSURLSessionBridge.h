/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <Foundation/Foundation.h>

@interface NSURLSessionBridge : NSObject

+ (NSURLSessionDataTask *)session:(NSURLSession *)session dataTaskWithURL:(NSURL *)url completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;
+ (NSURLSessionDataTask *)session:(NSURLSession *)session dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void(^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler;

+ (id)new NS_UNAVAILABLE;
- (id)init NS_UNAVAILABLE;

@end
