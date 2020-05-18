/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "TemplateURLSession.h"
@import ObjectiveC.message;

id (*objc_msgSendSuper_URLRequest)(struct objc_super *, SEL, NSURLRequest *) = (void *)&objc_msgSendSuper;
id (*objc_msgSendSuper_URLRequestWithCompletionHandler)(struct objc_super *, SEL, NSURLRequest *, void(^)(NSData *, NSURLResponse *, NSError *)) = (void *)&objc_msgSendSuper;

struct objc_super superStruct(id sself) {
    struct objc_super blockSuper = {
        .receiver = sself,
        .super_class = class_getSuperclass(object_getClass(sself))
    };
    return blockSuper;
}

// IMPORTANT NOTE: TemplateURLSession should NOT have "ivar"s other than what NSURLSession has
// Ivars change the memory layout of the class and needs to be added very carefully unless if it MUST be added
@implementation TemplateURLSession

- (NSURLRequest *)injected_interceptRequest:(NSURLRequest *)request {
    NSAssert(false, @"This method should not be run at runtime!");
    return request;
}
- (void)injected_observeTask:(NSURLSessionTask *)task {
    NSAssert(false, @"This method should not be run at runtime!");
}

// MARK: - Super method implementations

/*
 IMPORTANT NOTE: "super" keyword is resolved at compile-time,
 so [super dataTaskWithRequest:modifiedRequest] would resolve to NSURLSession.dataTaskWithRequest:
 as NSURLSession is the superclass of this class at compile-time.
 However, superclass of this method may be different at runtime.
 Eg: [NSURLSession shared] is _NSURLLocalSession, which is different than NSURLSession.
 */
- (NSURLSessionDataTask *)super_dataTaskWithRequest:(NSURLRequest *)request {
    struct objc_super ssuper = superStruct(self);
    return objc_msgSendSuper_URLRequest(&ssuper,
                                        @selector(dataTaskWithRequest:),
                                        request);
}
- (NSURLSessionDataTask *)super_dataTaskWithRequest:(NSURLRequest *)request
                                  completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    struct objc_super ssuper = superStruct(self);
    return objc_msgSendSuper_URLRequestWithCompletionHandler(&ssuper,
                                                             @selector(dataTaskWithRequest:completionHandler:),
                                                             request,
                                                             completionHandler);
}

// MARK: - Swizzled URLSession methods

// MARK: - URLSessionDataTask

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest
                             requestWithURL:url
                             cachePolicy:self.configuration.requestCachePolicy
                             timeoutInterval:self.configuration.timeoutIntervalForRequest];
    return [self dataTaskWithRequest:request];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLRequest *modifiedRequest = [self injected_interceptRequest:request];
    NSURLSessionDataTask *dataTask = [self super_dataTaskWithRequest:modifiedRequest];
    [self injected_observeTask:dataTask];
    return dataTask;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSURLRequest *request = [NSURLRequest
                             requestWithURL:url
                             cachePolicy:self.configuration.requestCachePolicy
                             timeoutInterval:self.configuration.timeoutIntervalForRequest];
    return [self dataTaskWithRequest:request completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSURLRequest *modifiedRequest = [self injected_interceptRequest:request];
    NSURLSessionDataTask *dataTask = [self super_dataTaskWithRequest:modifiedRequest
                                                   completionHandler:completionHandler];
    [self injected_observeTask:dataTask];
    return dataTask;
}
@end
