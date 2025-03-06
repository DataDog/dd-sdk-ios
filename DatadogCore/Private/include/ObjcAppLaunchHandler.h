/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// `AppLaunchHandler` tracks key timestamps in the app launch sequence,
/// as described in Apple's documentation:
/// https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence
@interface __dd_private_AppLaunchHandler : NSObject

typedef void (^UIApplicationDidBecomeActiveCallback) (NSTimeInterval);

/// The singleton instance of `AppLaunchHandler`.
@property (class, readonly) __dd_private_AppLaunchHandler *shared;

/// The timestamp when the application process was launched.
@property (atomic, readonly) NSDate* launchDate;

/// The time interval (in seconds) between the app process launch and
/// the `UIApplicationDidBecomeActiveNotification`. Returns `nil` if
/// the notification has not yet been received.
@property (atomic, readonly, nullable) NSNumber* launchTime;

/// Indicates whether the application was prewarmed by the system.
@property (atomic, readonly) BOOL isActivePrewarm;

/// Initializes an instance of `AppLaunchHandler` with the given process information.
///
/// - Parameter processInfo: The `NSProcessInfo` instance used to retrieve environment variables,
///   including information about whether the app was prewarmed.
- (instancetype)initWithProcessInfo:(NSProcessInfo *)processInfo;

/// Observes the given notification center for application lifecycle events.
///
/// This method listens for the application becoming active and updates launch-related timestamps accordingly.
///
/// - Parameter notificationCenter: The `NSNotificationCenter` instance used to observe application state changes.
- (void)observeNotificationCenter:(NSNotificationCenter *)notificationCenter;

/// Sets a callback to be invoked when the application becomes active.
///
/// The callback receives the time interval from launch to activation.
/// If the application became active before setting the callback, it will not be triggered.
///
/// - Parameter callback: A closure executed upon app activation.
- (void)setApplicationDidBecomeActiveCallback:(UIApplicationDidBecomeActiveCallback)callback;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
