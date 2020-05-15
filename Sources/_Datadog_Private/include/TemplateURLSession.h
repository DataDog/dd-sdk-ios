//
//  TemplateURLSession.h
//  Datadog
//
//  Created by Mert Buran on 15/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

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
