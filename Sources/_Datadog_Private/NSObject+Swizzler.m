/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

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
