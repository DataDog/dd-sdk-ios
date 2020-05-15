/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#import "Swizzler.h"
#import "SwizzlerError.h"
#import "NSObject+Swizzler.h"
@import ObjectiveC.runtime;

@implementation Swizzler

+ (BOOL)swizzle:(NSObject *)object
           with:(Class)newClass
          error:(NSError **)error {
    if (*error != nil) { return NO; }
    Class currentClass = object_getClass(object);
    NSString *currentClassName = NSStringFromClass(currentClass);
    if (currentClassName == nil) {
        *error = [SwizzlerError objectDoesNotHaveAClass];
        return NO;
    }

    if (object.originalClassName == nil) {
        object.originalClassName = currentClassName;
    }

    if (class_getInstanceSize(currentClass) != class_getInstanceSize(newClass)) {
        *error = [SwizzlerError classSizeIsDifferentWithPreviousClass:currentClass newClass:newClass];
        return NO;
    }

    object_setClass(object, newClass);
    return YES;
}

+ (BOOL)     unswizzle:(NSObject *)swizzledObject
            ifPrefixed:(NSString *)prefix
andDisposeDynamicClass:(BOOL)disposeDynamicClass
                 error:(NSError **)error {
    if (*error != nil) { return NO; }

    NSString *originalClassName = swizzledObject.originalClassName;
    Class originalClass = NSClassFromString(originalClassName);

    if (originalClass == nil) {
        *error = [SwizzlerError objectWasNotSwizzled:swizzledObject withPrefix:nil];
        return NO;
    } else if (prefix != nil) {
        // compare class names
        NSString *prefixedOriginalClassName = [self string:originalClassName
                                                withPrefix:prefix];
        NSString *currentClassName = NSStringFromClass(object_getClass(swizzledObject));
        if ([currentClassName isEqualToString:prefixedOriginalClassName] == NO) {
            *error = [SwizzlerError objectWasNotSwizzled:swizzledObject withPrefix:prefix];
            return NO;
        }
    }

    Class swizzledClass = object_setClass(swizzledObject, originalClass);
    if (swizzledClass != nil) {
        swizzledObject.originalClassName = nil;
        if (disposeDynamicClass) {
            objc_disposeClassPair(swizzledClass);
        }
    }
    return YES;
}

+ (nullable Class)dynamicClassWith:(NSString *)dynamicClassPrefix
                        superclass:(Class)superklass
                         configure:(BOOL(^)(Class newClass))configure {
    // Get dynamic class if already registered at runtime
    NSString *superclassName = NSStringFromClass(superklass);
    const char *dynamicClassName = [self string:superclassName
                                     withPrefix:dynamicClassPrefix].UTF8String;
    Class dynamicClass = objc_lookUpClass(dynamicClassName);
    if (dynamicClass == nil) {
        Class newClass = objc_allocateClassPair(superklass,
                                                dynamicClassName,
                                                0);
        if (newClass == nil) {
            // New class cannot be created due to an unknown reason
            return nil;
        }
        if (configure != nil) {
            if (configure(newClass) == NO) {
                // NewClass could not be configured successfully
                objc_disposeClassPair(newClass);
                return nil;
            }
        }
        objc_registerClassPair(newClass);
        dynamicClass = newClass;
    }
    return dynamicClass;
}

+ (BOOL)addMethodsOf:(Class)templateClass
                  to:(Class)newClass
               error:(NSError **)error {
    if (*error != nil) { return NO; }
    // 1. Get list of methods from templateClass
    unsigned int methodCount = 0;
    Method *sourceMethods = class_copyMethodList(templateClass,
                                                 &methodCount);
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        // 2. Get a method from templateClass
        Method method = sourceMethods[methodIndex];

        SEL selector = method_getName(method);
        IMP implementation = method_getImplementation(method);
        const char *typeEncoding = method_getTypeEncoding(method);
        BOOL methodAdded = class_addMethod(newClass,
                                           selector,
                                           implementation,
                                           typeEncoding);
        if (!methodAdded) {
            *error = [SwizzlerError selector:NSStringFromSelector(selector)
                      wasAlreadyAddedToClass:newClass];
            return NO;
        }
    }
    return YES;
}

+ (BOOL)setBlock:(id)blockIMP
implementationOf:(SEL)selector
         inClass:(Class)klass
           error:(NSError **)error {
    if (*error != nil) { return NO; }
    Method method = class_getInstanceMethod(klass, selector);
    if (method == nil) {
        *error = [SwizzlerError selector:NSStringFromSelector(selector) doesNotExistInClass:klass];
        return NO;
    }
    IMP concreteIMP = imp_implementationWithBlock(blockIMP);
    method_setImplementation(method, concreteIMP);
    return YES;
}

// MARK: - Private helpers

+ (NSString *)string:(NSString *)baseString withPrefix:(NSString *)prefix {
    return [NSString stringWithFormat:@"%@%@", prefix, baseString];
}

@end
