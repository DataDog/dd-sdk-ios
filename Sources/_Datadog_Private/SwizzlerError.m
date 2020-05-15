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

+ (instancetype)dynamicClassAlreadyExistsWith:(NSString *)prefix
                                      basedOn:(NSString *)superclassName {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Dynamic class, %@%@, already exists at runtime",
                                    prefix,
                                    superclassName],
        NSLocalizedRecoverySuggestionErrorKey: @"You can use enforceCreateNewClass:NO to get already existed dynamic class"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:2 userInfo:userInfo];
}

+ (instancetype)objectWasNotSwizzled:(NSObject *)object withPrefix:(NSString *)prefix {
    NSString *desc = [NSString stringWithFormat:@"%@, class: %@, cannot be unswizzled since it was not swizzled before with %@ prefix",
                      object,
                      NSStringFromClass(object_getClass(object)),
                      prefix];
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: desc};
    return [SwizzlerError errorWithDomain:[self domain] code:3 userInfo:userInfo];
}

+ (instancetype)objectIsNil {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Object to be unswizzled is nil"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:4 userInfo:userInfo];
}

+ (instancetype)objectDoesNotHaveAClass {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Object does not have a class; possibly nil"
    };
    return [SwizzlerError errorWithDomain:[self domain] code:5 userInfo:userInfo];
}

+ (instancetype)selector:(NSString *)selector wasAlreadyAddedToClass:(Class)klass {
    NSString *desc = [NSString stringWithFormat:@"%@ was already added to %@, cannot be added again",
                      selector,
                      NSStringFromClass(klass)];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: desc};
    return [SwizzlerError errorWithDomain:[self domain] code:6 userInfo:userInfo];
}

+ (instancetype)selector:(NSString *)selector doesNotExistInClass:(Class)klass {
    NSString *desc = [NSString stringWithFormat:@"Selector %@ does not exist in class %@",
                      selector,
                      NSStringFromClass(klass)];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: desc};
    return [SwizzlerError errorWithDomain:[self domain] code:7 userInfo:userInfo];
}

@end
