//
//  Swizzler.h
//  Datadog
//
//  Created by Mert Buran on 11/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Swizzler : NSObject

+ (BOOL)    swizzle:(NSURLSession *)session
 requestInterceptor:(NSURLRequest *(^)(NSURLRequest *))requestInterceptor
       taskObserver:(void(^)(NSURLSessionTask *))taskObserver
enforceDynamicClassCreation:(BOOL)enforceCreateNewClass
              error:(NSError **)error;

+ (BOOL)    unswizzle:(nullable NSURLSession *)swizzledSession
andRemoveDynamicClass:(BOOL)removeDynamicClass
                error:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
