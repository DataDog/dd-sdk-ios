//
//  Swizzler.h
//  Datadog
//
//  Created by Mert Buran on 11/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// NOTE: Swizzler methods are not thread-safe

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

+ (nullable Class)dynamicClassWith:(NSString *)dynamicClassPrefix
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
