/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returned when `__dd_private_getTaskPolicy()` fails to query the kernel (return code != KERN_SUCCESS).
FOUNDATION_EXPORT const NSInteger __dd_private_TASK_POLICY_KERN_FAILURE;

/// Returned when `__dd_private_getTaskPolicy()` falls back to the system’s default policy (get_default == TRUE).
FOUNDATION_EXPORT const NSInteger __dd_private_TASK_POLICY_DEFAULTED;

/// Returned when `__dd_private_getTaskPolicy()` queries are unsupported on the current platform (e.g., tvOS).
FOUNDATION_EXPORT const NSInteger __dd_private_TASK_POLICY_UNAVAILABLE;

/// `AppLaunchHandler` tracks key timestamps in the app launch sequence, as described in Apple's documentation:
/// https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence
@interface __dd_private_AppLaunchHandler : NSObject

/// Callback block invoked when the app transitions to an active state.
///
/// - Parameter timeInterval: The elapsed time, in seconds, from process launch to the delivery of the `didBecomeActive` notification.
typedef void (^UIApplicationDidBecomeActiveCallback)(NSTimeInterval timeInterval);

/// Shared singleton instance.
@property (class, nonatomic, readonly) __dd_private_AppLaunchHandler *shared;

/// The current process’s task policy role (`task_role_t`), indicating how the process was started (e.g., user vs background launch).
/// On success, the property contains the raw [`policy.role`](https://developer.apple.com/documentation/kernel/task_role_t) value;
/// otherwise, it returns one of the special constants:
/// - `__dd_private_TASK_POLICY_KERN_FAILURE`
/// - `__dd_private_TASK_POLICY_DEFAULTED`
/// - `__dd_private_TASK_POLICY_UNAVAILABLE`
@property (nonatomic, readonly) NSInteger taskPolicyRole;

/// The timestamp when the application process was launched.
@property (nonatomic, readonly) NSDate *processLaunchDate;

/// The time interval (in seconds) between process launch and app activation (`didBecomeActive`), or nil if not yet activated.
@property (nonatomic, readonly, nullable) NSNumber *timeToDidBecomeActive;

/// Observes the given notification center for application lifecycle events.
///
/// This method listens for the application becoming active and updates launch-related timestamps accordingly.
///
/// - Parameter notificationCenter: The `NSNotificationCenter` instance used to observe application state changes.
- (void)observeNotificationCenter:(NSNotificationCenter *)notificationCenter;

/// Sets a callback to be invoked when the application becomes active.
///
/// The callback receives the time interval from process launch to app activation.
/// The callback is triggered only once upon the next `UIApplicationDidBecomeActiveNotification`
/// and is not retained for subsequent activations.
///
/// - Parameter callback: A closure executed upon app activation.
- (void)setApplicationDidBecomeActiveCallback:(nonnull UIApplicationDidBecomeActiveCallback)callback;

- (instancetype)init;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
