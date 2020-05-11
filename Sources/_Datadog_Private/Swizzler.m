/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#import "Swizzler.h"
#import "TemplateURLSession.h"
#import "SwizzlerError.h"
@import ObjectiveC.runtime;

/*
 TemplateURLSession:
 • overridden methods: dataTaskWithURL:, dataTaskWithURLRequest:, etc.
 • compile-time placeholder methods: injected_interceptRequest:, injected_observeTask:, super_dataTaskWithURLRequest:, etc.
 1. injected_ methods
 2. super_ methods
 Swizzler:
 1. take object
 2. lookup dynamic class; early return if exists
 3. create if not exists
 • add instance methods from TemplateURLSession
 • add injected methods from blocks passed as parameters
 4. change class of object

 Open questions:
 1. what to do with URLTaskPublisher? it's Swift struct, un-swizzable
 2. profile dynamic class, does it add overhead beyond limits?
 3. thread safety in swizzling?
 */

@implementation Swizzler

+ (Class)templateClass {
    Class template = TemplateURLSession.class;
    NSAssert([class_getSuperclass(template) isEqual:NSURLSession.class],
             @"Swizzler.templateClass must be a NSURLSession subclass!");
    return template;
}

+ (NSString *)dynamicClassNameForSuperclass:(Class)superclass {
    static NSString *dynamicClassPrefix = @"_Datadog";
    const char *superclassName = class_getName(superclass);
    NSString *dynamicClassName = [NSString stringWithFormat:@"%@%s",
                                  dynamicClassPrefix,
                                  superclassName];
    return dynamicClassName;
}

+ (BOOL)    swizzle:(NSURLSession *)session
 requestInterceptor:(NSURLRequest *(^)(NSURLRequest *))requestInterceptor
       taskObserver:(void(^)(NSURLSessionTask *))taskObserver
enforceDynamicClassCreation:(BOOL)enforceCreateNewClass
              error:(NSError **)error {
    if (*error != nil) { return NO; }

    Class superclass = object_getClass(session);
    // Get dynamic class if already registered at runtime
    const char *dynamicClassName = [self dynamicClassNameForSuperclass:superclass].UTF8String;
    Class dynamicClass = objc_lookUpClass(dynamicClassName);

    if (enforceCreateNewClass && dynamicClass != nil) {
        *error = [SwizzlerError dynamicClassAlreadyExists:dynamicClass];
        return NO;
    }

    // Create dynamic class if it wasn't registered at runtime before
    if (dynamicClass == nil) {
        Class newClass = objc_allocateClassPair(superclass, dynamicClassName, 0);
        // Decorate newClass with methods
        [self addMethodsOfClass:[self templateClass]
             requestInterceptor:requestInterceptor
                   taskObserver:taskObserver
                        toClass:newClass];
        objc_registerClassPair(newClass);
        dynamicClass = newClass;
    }

    if (class_getInstanceSize(superclass) != class_getInstanceSize(dynamicClass)) {
        *error = [SwizzlerError classSizeIsDifferentWithPreviousClass:superclass
                                                             newClass:dynamicClass];
    }
    
    if (*error == nil) {
        object_setClass(session, dynamicClass);
        return YES;
    }
    return NO;
}

+ (void)addMethodsOfClass:(Class)templateClass
       requestInterceptor:(NSURLRequest *(^)(NSURLRequest *))requestInterceptor
             taskObserver:(void(^)(NSURLSessionTask *))taskObserver
                  toClass:(Class)newClass {
    // 1. Get list of methods from TemplateURLSession
    unsigned int methodCount = 0;
    Method *sourceMethods = class_copyMethodList(templateClass,
                                                 &methodCount);
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        // 2. Get a method from TemplateURLSession
        Method method = sourceMethods[methodIndex];

        SEL selector = method_getName(method);
        NSString *selectorString = NSStringFromSelector(selector);

        if ([selectorString hasPrefix:@"injected_"]) {
            // Blocks* that are passed as function parameters are turned into methods of newClass
            // *: requestInterceptor and taskObserver
            const char *typeEncoding = method_getTypeEncoding(method);
            if ([selectorString isEqualToString:NSStringFromSelector(@selector(injected_interceptRequest:))]) {
                IMP requestInterceptorIMP = imp_implementationWithBlock((NSURLRequest *)^(__unsafe_unretained id blockSelf, NSURLRequest *originalRequest) {
                    NSURLRequest *modifiedRequest = requestInterceptor(originalRequest);
                    return modifiedRequest;
                });
                class_addMethod(newClass,
                                selector,
                                requestInterceptorIMP,
                                typeEncoding);
            } else if ([selectorString isEqualToString:NSStringFromSelector(@selector(injected_observeTask:))]) {
                IMP taskObserverIMP = imp_implementationWithBlock(^(__unsafe_unretained id blockSelf, NSURLSessionTask *task) {
                    return taskObserver(task);
                });
                class_addMethod(newClass,
                                selector,
                                taskObserverIMP,
                                typeEncoding);
            } /* else {
               TODO: RUMM-300 Report unsupported injected method defined in TemplateURLSession
               } */
        } else {
            // add method normally
            IMP implementation = method_getImplementation(method);
            const char *typeEncoding = method_getTypeEncoding(method);
            class_addMethod(newClass,
                            selector,
                            implementation,
                            typeEncoding);
        }
    }
}

+ (BOOL)    unswizzle:(NSURLSession *)swizzledSession
andRemoveDynamicClass:(BOOL)removeDynamicClass
                error:(NSError **)error {
    if (*error != nil) { return NO; }

    if (swizzledSession == nil) {
        *error = [SwizzlerError objectIsNil];
        return NO;
    }
    Class klass = object_getClass(swizzledSession);
    Class superklass = class_getSuperclass(klass);
    NSString *dynamicKlassName = [self dynamicClassNameForSuperclass:superklass];
    if ([dynamicKlassName isEqualToString:NSStringFromClass(klass)] == NO) {
        // swizzledSession does NOT have a dynamic class!
        *error = [SwizzlerError objectWasNotSwizzled:swizzledSession];
    } else if (class_getInstanceSize(superklass) != class_getInstanceSize(klass)) {
        *error = [SwizzlerError classSizeIsDifferentWithPreviousClass:klass newClass:superklass];
    }

    if (*error == nil) {
        object_setClass(swizzledSession, superklass);
        if (removeDynamicClass) {
            objc_disposeClassPair(klass);
        }
        return YES;
    }
    return NO;
}

@end
