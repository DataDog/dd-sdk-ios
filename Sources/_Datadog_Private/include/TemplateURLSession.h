/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TemplateURLSession : NSURLSession

// MARK: - Injected method placeholders
// injected methods are NEVER used at runtime
// Their implementations at runtime are injected by URLSessionSwizzler
- (NSURLRequest *)injected_interceptRequest:(NSURLRequest *)request;
- (void)injected_observeTask:(NSURLSessionTask *)task;
@end

NS_ASSUME_NONNULL_END
