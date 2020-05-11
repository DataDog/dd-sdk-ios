//
//  SwizzlerError.m
//  Datadog
//
//  Created by Mert Buran on 13/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import "SwizzlerError.h"
@import ObjectiveC.runtime;

@implementation SwizzlerError

+ (NSErrorDomain)domain {
    return @"DDSwizzler";
}

+ (instancetype)classSizeIsDifferentWithPreviousClass:(Class)prevClass newClass:(Class)newClass {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ instance has the size of %lu whereas %@ instance has the size of %lu", prevClass, class_getInstanceSize(prevClass), newClass, class_getInstanceSize(newClass)],
        NSLocalizedRecoverySuggestionErrorKey: @"If new class has extra ivars, please remove them as they may change memory layout of the class"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:1 userInfo:userInfo];
}

+ (instancetype)dynamicClassAlreadyExists:(Class)dynamicClass {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ already exists at runtime", dynamicClass],
        NSLocalizedRecoverySuggestionErrorKey: @"You can use enforceCreateNewClass:NO to get already existed dynamic class"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:2 userInfo:userInfo];
}

+ (instancetype)objectWasNotSwizzled:(NSObject *)object {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ cannot be unswizzled since it was not swizzled before", object]
    };
    return [SwizzlerError errorWithDomain:[self domain] code:3 userInfo:userInfo];
}

+ (instancetype)objectIsNil {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Object to be unswizzled is nil"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:4 userInfo:userInfo];
}

@end
