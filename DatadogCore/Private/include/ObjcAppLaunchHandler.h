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

/// Callback block invoked when the app receives a UIApplication notification.
///
/// - Parameter didFinishLaunchingTimeInterval: The date when the `didFinishLaunching` notification triggered.
/// - Parameter didBecomeActiveTimeInterval: The date when the `didBecomeActive` notification triggered.
typedef void (^UIApplicationNotificationCallback)(NSDate * _Nullable didFinishLaunchingTimeInterval,
                                                  NSDate * _Nullable didBecomeActiveTimeInterval);

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

/// The timestamp when the SDK was loaded.
@property (nonatomic, readonly) NSDate *runtimeLoadDate;

/// The timestamp right before the @c main() is executed.
@property (nonatomic, readonly) NSDate *runtimePreMainDate;

/// The timestamp when the app did finish launching (`didFinishLaunching`).
/// `nil` if not yet launched.
@property (nonatomic, readonly, nullable) NSDate *didFinishLaunchingDate;

/// The timestamp when the app was activated (`didBecomeActive`).
/// `nil` if not yet activated.
@property (nonatomic, readonly, nullable) NSDate *didBecomeActiveDate;


/// Observes the given notification center for application lifecycle events.
///
/// This method listens for the application becoming active and updates launch-related timestamps accordingly.
///
/// - Parameter notificationCenter: The `NSNotificationCenter` instance used to observe application state changes.
- (void)observeNotificationCenter:(NSNotificationCenter *)notificationCenter;

/// Sets a callback to be invoked when the application receives UIApplication notifications.
///
/// - Parameter callback: A closure executed upon app activation.
- (void)setApplicationNotificationCallback:(nonnull UIApplicationNotificationCallback)callback;

- (instancetype)init;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
