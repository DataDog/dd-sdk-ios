//
//  TemplateURLSession.h
//  Datadog
//
//  Created by Mert Buran on 13/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TemplateURLSession : NSURLSession
// injected methods are NEVER used at runtime
// Their implementations at runtime are injected by Swizzler
- (NSURLRequest *)injected_interceptRequest:(NSURLRequest *)request;
- (void)injected_observeTask:(NSURLSessionTask *)task;
@end

NS_ASSUME_NONNULL_END
