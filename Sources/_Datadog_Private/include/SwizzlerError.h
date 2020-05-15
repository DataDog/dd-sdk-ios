//
//  SwizzlerError.h
//  Datadog
//
//  Created by Mert Buran on 13/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SwizzlerError : NSError
/*
 Changing class of session should NOT change memory bounds of the object
 If new class is larger than the old one, the object overflows onto other objects
 If new class is smaller, some memory blocks may stay unused and therefore wasted
 @param prevClass: current class of the instance
 @param newClass: class with which the instance was to be swizzled
 */
+ (instancetype)classSizeIsDifferentWithPreviousClass:(Class)prevClass
                                             newClass:(Class)newClass;

+ (instancetype)dynamicClassAlreadyExistsWith:(NSString *)prefix
                                      basedOn:(NSString *)superclassName;
+ (instancetype)objectWasNotSwizzled:(NSObject *)object
                          withPrefix:(nullable NSString *)prefix;
+ (instancetype)objectIsNil;
+ (instancetype)objectDoesNotHaveAClass;
+ (instancetype)selector:(NSString *)selector wasAlreadyAddedToClass:(Class)klass;
+ (instancetype)selector:(NSString *)selector doesNotExistInClass:(Class)klass;
@end

NS_ASSUME_NONNULL_END
