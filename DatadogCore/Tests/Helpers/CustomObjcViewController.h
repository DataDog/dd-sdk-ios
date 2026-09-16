/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <TargetConditionals.h>

#if !TARGET_OS_WATCH

#if __has_include(<UIKit/UIKit.h>)

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomObjcViewController : UIViewController

@end

NS_ASSUME_NONNULL_END

#else

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomObjcViewController : NSViewController

@end

NS_ASSUME_NONNULL_END

#endif

#endif
