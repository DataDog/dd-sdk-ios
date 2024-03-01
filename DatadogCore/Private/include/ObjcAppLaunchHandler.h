/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#if TARGET_OS_IPHONE
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// `AppLaunchHandler` aims to track some times as part of the sequence
/// described in Apple's "About the App Launch Sequence"
///
/// ref. https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence
@interface __dd_private_AppLaunchHandler : NSObject

typedef void (^UIApplicationDidBecomeActiveCallback) (NSTimeInterval);

/// Sole instance of the Application Launch Handler.
@property (class, readonly) __dd_private_AppLaunchHandler *shared;

/// Returns the Application process launch date.
@property (atomic, readonly) NSDate* launchDate;

/// Returns the time interval in seconds between startup of the application process and the
/// `UIApplicationDidBecomeActiveNotification`. Or `nil` If the
/// `UIApplicationDidBecomeActiveNotification` has not been reached yet.
@property (atomic, readonly, nullable) NSNumber* launchTime;

/// Returns `true` when the application is pre-warmed.
///
/// System sets environment variable `ActivePrewarm` to 1 when app is pre-warmed.
@property (atomic, readonly) BOOL isActivePrewarm;

/// Sets the callback to be invoked when the application becomes active.
///
/// The closure get the updated handler as argument. You will not get any
/// notification if the application became active before setting the callback
/// 
/// - Parameter callback: The callback closure.
- (void)setApplicationDidBecomeActiveCallback:(UIApplicationDidBecomeActiveCallback)callback;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
#endif
