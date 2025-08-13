/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <pthread.h>
#import <sys/sysctl.h>
#import <mach/mach.h>

#import "ObjcAppLaunchHandler.h"

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

@interface PreMainHelper : NSObject
+ (void)recordLoadExecution;
+ (void)recordFirstAttribute;
+ (void)recordSecondAttribute;
+ (void)recordMainExecution;
@end

/**
 * Constructor priority must be bounded between 101 and 65535 inclusive, see
 * https://gcc.gnu.org/onlinedocs/gcc-4.7.0/gcc/Function-Attributes.html and
 * https://gcc.gnu.org/onlinedocs/gcc-4.7.0/gcc/C_002b_002b-Attributes.html#C_002b_002b-Attributes
 * The constructor attribute causes the function to be called automatically before execution enters
 * @c main() . The lower the priority number, the sooner the constructor runs, which means 100 runs
 * before 101. As we want to be as close to @c main() as possible, we choose a high number.
 */

// Constructor priority must be between 101 and 65535 inclusive
enum { DDConstructorPriority = 65535 };

// The constructor attribute causes the function to be called automatically before execution enters main().
// The higher the priority, the closest to the main() call.
// More information at https://gcc.gnu.org/onlinedocs/gcc-4.7.0/gcc/C_002b_002b-Attributes.html#C_002b_002b-Attributes
__used __attribute__((constructor(DDConstructorPriority)))
static void recordPreMainInitialization(void) {
    [PreMainHelper recordSecondAttribute];
    [__dd_private_AppLaunchHandler.shared setPreMainDate: CFAbsoluteTimeGetCurrent()];
    NSLog(@"hello1");
}

__used __attribute__((constructor(65535)))
static void recordPreMainInitialization2(void) {
    NSLog(@"hello2");
}

// Runs before main()
__used __attribute__((constructor(101)))
static void recordPrePreMainInitialization(void) {
    [PreMainHelper recordFirstAttribute];
    [__dd_private_AppLaunchHandler.shared setPreMainDate: CFAbsoluteTimeGetCurrent()];
    NSLog(@"hello0");
}

/// Constants for special task policy results
/// Returned when the kernel query fails (kernel_result != KERN_SUCCESS).
const NSInteger __dd_private_TASK_POLICY_KERN_FAILURE   = -999;
/// Returned when the policy falls back to the system default (get_default == TRUE).
const NSInteger __dd_private_TASK_POLICY_DEFAULTED      = -99;
/// Returned when task policy queries are unsupported on this platform (e.g., tvOS).
const NSInteger __dd_private_TASK_POLICY_UNAVAILABLE    = -9;

/// Retrieves the process start timestamp relative to the 1 January 2001 reference date.
///
/// @param timeInterval Pointer to an NSTimeInterval where the result will be stored.
///                     On success, *timeInterval is set to the process start offset in seconds.
/// @return 0 on success; non-zero errno value on failure.
int processStartTimeIntervalSinceReferenceDate(NSTimeInterval *timeInterval);

@implementation __dd_private_AppLaunchHandler {
    NSTimeInterval _processLaunchDate;
    NSTimeInterval _timeToDidBecomeActive;
    NSTimeInterval _preMainDate;
    UIApplicationDidBecomeActiveCallback _applicationDidBecomeActiveCallback;
}

static __dd_private_AppLaunchHandler *_shared;

+ (void)load {
    [PreMainHelper recordLoadExecution];
    _shared = [[self alloc] init];
    [_shared observeNotificationCenter:NSNotificationCenter.defaultCenter];
}

+ (__dd_private_AppLaunchHandler *)shared {
    return _shared;
}

- (instancetype)init {
    NSTimeInterval startTime;
    if (processStartTimeIntervalSinceReferenceDate(&startTime) != 0) {
        startTime = CFAbsoluteTimeGetCurrent();
    }
    self = [super init];
    if (!self) return nil;

    _processLaunchDate = startTime;
    _applicationDidBecomeActiveCallback = ^(NSTimeInterval _) {};
    return self;
}

- (void)observeNotificationCenter:(NSNotificationCenter *)notificationCenter {
    NSString *notificationName;
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
    notificationName = UIApplicationDidBecomeActiveNotification;
#elif TARGET_OS_OSX
    notificationName = NSApplicationDidBecomeActiveNotification;
#endif

    if (!notificationName || !notificationCenter) {
        return;
    }

    __weak NSNotificationCenter *weakCenter = notificationCenter;
    __block id __unused token = [notificationCenter addObserverForName:notificationName
                                                                object:nil
                                                                 queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *_){
        @synchronized(self) {
            NSTimeInterval time = CFAbsoluteTimeGetCurrent() - self->_processLaunchDate;
            self->_timeToDidBecomeActive = time;
            self->_applicationDidBecomeActiveCallback(time);
        }

        [weakCenter removeObserver:token];
        token = nil;
    }];
}

/// Retrieves the current process’s task policy role (`task_role_t`).
/// Returns the raw `policy.role` on success, or one of the special `__dd_private_TASK_POLICY_*` constants.
- (NSInteger)taskPolicyRole {
#if TARGET_OS_TV || TARGET_OS_WATCH
    return __dd_private_TASK_POLICY_UNAVAILABLE;
#else
    task_category_policy_data_t policy;
    mach_msg_type_number_t count = TASK_CATEGORY_POLICY_COUNT;
    boolean_t get_default = FALSE;
    kern_return_t kernel_result = task_policy_get(mach_task_self(),
                                                  TASK_CATEGORY_POLICY,
                                                  (task_policy_t)&policy,
                                                  &count,
                                                  &get_default);
    if (kernel_result != KERN_SUCCESS) {
        return __dd_private_TASK_POLICY_KERN_FAILURE;
    }
    if (get_default) {
        return __dd_private_TASK_POLICY_DEFAULTED;
    }
    return policy.role;
#endif
}

- (NSDate *)processLaunchDate {
    @synchronized(self) {
        return [NSDate dateWithTimeIntervalSinceReferenceDate:_processLaunchDate];
    }
}

- (NSNumber *)timeToDidBecomeActive {
    @synchronized(self) {
        return _timeToDidBecomeActive > 0 ? @(_timeToDidBecomeActive) : nil;
    }
}

- (void)setPreMainDate:(CFAbsoluteTime) preMainDate {
    @synchronized(self) {
        _preMainDate = preMainDate;
    }
}

- (void)setApplicationDidBecomeActiveCallback:(UIApplicationDidBecomeActiveCallback)callback {
    @synchronized(self) {
        _applicationDidBecomeActiveCallback = callback;
    }
}

@end

int processStartTimeIntervalSinceReferenceDate(NSTimeInterval *timeInterval) {
    // Query the current process' start time:
    // https://www.freebsd.org/cgi/man.cgi?sysctl(3)
    // https://github.com/darwin-on-arm/xnu/blob/707bfdc4e9a46e3612e53994fffc64542d3f7e72/bsd/sys/sysctl.h#L681
    // https://github.com/darwin-on-arm/xnu/blob/707bfdc4e9a46e3612e53994fffc64542d3f7e72/bsd/sys/proc.h#L97
    struct kinfo_proc kip;
    size_t kipSize = sizeof(kip);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    int res = sysctl(mib, 4, &kip, &kipSize, NULL, 0);
    if (res != 0) return res;

    // The process' start time is provided relative to 1 Jan 1970
    struct timeval startTime = kip.kp_proc.p_starttime;
    // Multiplication with 1.0 ensure we don't round to 0 with integer division
    NSTimeInterval processStartTime = startTime.tv_sec + (1.0 * startTime.tv_usec) / USEC_PER_SEC;
    // Convert to time since 1 Jan 2001 to align with CFAbsoluteTimeGetCurrent()
    *timeInterval = processStartTime - kCFAbsoluteTimeIntervalSince1970;
    return res;
}
