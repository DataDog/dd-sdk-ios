/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Swizzler : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (BOOL)swizzle:(NSObject *)object
           with:(Class)newClass
          error:(NSError **)error;

+ (BOOL)     unswizzle:(NSObject *)swizzledObject
            ifPrefixed:(nullable NSString *)prefix
andDisposeDynamicClass:(BOOL)disposeDynamicClass
                 error:(NSError **)error;

+ (nullable Class)createClassWith:(NSString *)dynamicClassPrefix
                       superclass:(Class)superklass
                        configure:(BOOL(^)(Class newClass))configure;

+ (BOOL)addMethodsOf:(Class)templateClass
                  to:(Class)newClass
               error:(NSError **)error;

+ (BOOL)setBlock:(id)blockIMP
implementationOf:(SEL)selector
         inClass:(Class)klass
           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
