//
//  NSObject+Swizzler.h
//  Datadog
//
//  Created by Mert Buran on 15/05/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (Swizzler)

@property (atomic, strong, nullable) NSString *originalClassName;

@end

NS_ASSUME_NONNULL_END
