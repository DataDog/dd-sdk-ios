//
//  NSObject+Swizzler.m
//  Datadog
//
//  Created by Mert Buran on 15/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import "NSObject+Swizzler.h"
@import ObjectiveC.runtime;

@implementation NSObject (Swizzler)
static const void *originalClassAssociatedObjectKey = @"__swizzler_originalClass";
- (void)setOriginalClassName:(NSString *)originalClassName {
    objc_setAssociatedObject(self,
                             originalClassAssociatedObjectKey,
                             originalClassName,
                             OBJC_ASSOCIATION_RETAIN);
}
- (NSString *)originalClassName {
    return objc_getAssociatedObject(self, originalClassAssociatedObjectKey);
}
@end
