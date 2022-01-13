/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "ObjcAppLaunchHandler.h"
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <pthread.h>

// `AppLaunchHandler` aims to track some times as part of the sequence described in Apple's "About the App Launch Sequence"
// https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence

#define IS_ACTIVE_PREWARM [NSProcessInfo.processInfo.environment[@"ActivePrewarm"] isEqual:@"1"]

// A Read-Write lock to allow concurrent reads of TimeToApplicationDidBecomeActive, unless the initial (and only) write is locking it.
static pthread_rwlock_t rwLock;
// The framework load time  in seconds relative to the absolute reference date of Jan 1 2001 00:00:00 GMT.
static NSTimeInterval FrameworkLoadTime = 0.0;
// The time when UIApplicationMain instantiante UIApplication.
static NSTimeInterval UIApplicationInstantiateSingletonTime = 0.0;
// The time when receiving UIApplicationDidBecomeActiveNotification.
static NSTimeInterval UIApplicationDidBecomeActiveNotificationTime = 0.0;
// The cold start threshold in seconds. Launch Time greater than this threshold should be considered as
// pre-warmed.
static NSTimeInterval ColdStartThreshold = 20;

NS_INLINE NSTimeInterval ProcessStartTime() {
    // Query the current process' start time:
    // https://www.freebsd.org/cgi/man.cgi?sysctl(3)
    // https://github.com/darwin-on-arm/xnu/blob/707bfdc4e9a46e3612e53994fffc64542d3f7e72/bsd/sys/sysctl.h#L681
    // https://github.com/darwin-on-arm/xnu/blob/707bfdc4e9a46e3612e53994fffc64542d3f7e72/bsd/sys/proc.h#L97

    struct kinfo_proc kip;
    size_t kipSize = sizeof(kip);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    int res = sysctl(mib, 4, &kip, &kipSize, NULL, 0);

    if (res == 0) {
        // The process' start time is provided relative to 1 Jan 1970
        struct timeval startTime = kip.kp_proc.p_starttime;
        NSTimeInterval processStartTime = startTime.tv_sec + startTime.tv_usec / USEC_PER_SEC;
        // Convert to time since 1 Jan 2001 to align with CFAbsoluteTimeGetCurrent()
        processStartTime -= kCFAbsoluteTimeIntervalSince1970;
        return processStartTime;
    }

    // Fallback to less accurate delta with DD's framework load time
    return FrameworkLoadTime;
}

@interface AppLaunchHandler : NSObject
@end

@implementation AppLaunchHandler

+ (void)load {
    pthread_rwlock_init(&rwLock, NULL);

    // This is called at the `_Datadog_Private` load time, keep the work minimal
    FrameworkLoadTime = CFAbsoluteTimeGetCurrent();

    NSNotificationCenter * __weak center = NSNotificationCenter.defaultCenter;
    id __weak __block token = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                                  object:nil
                                                   queue:NSOperationQueue.mainQueue
                                              usingBlock:^(NSNotification *_){
        pthread_rwlock_wrlock(&rwLock);
        UIApplicationDidBecomeActiveNotificationTime = CFAbsoluteTimeGetCurrent();
        pthread_rwlock_unlock(&rwLock);
        [center removeObserver:token];
    }];
}

@end

@implementation UIApplication (Tracking)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_exchangeImplementations(
            class_getInstanceMethod(self, @selector(init)),
            class_getInstanceMethod(self, @selector(dd_init))
        );
    });
}

- (instancetype)dd_init {
    pthread_rwlock_wrlock(&rwLock);
    UIApplicationInstantiateSingletonTime = CFAbsoluteTimeGetCurrent();
    pthread_rwlock_unlock(&rwLock);
    // Invoke original init
    return [self dd_init];
}

@end

CFTimeInterval __dd_private_AppLaunchTime() {
    pthread_rwlock_rdlock(&rwLock);

    CFTimeInterval time = UIApplicationDidBecomeActiveNotificationTime;
    if (!time) {
        time = CFAbsoluteTimeGetCurrent();
    }

    NSTimeInterval launchTime = time - ProcessStartTime();
    if (IS_ACTIVE_PREWARM || launchTime > ColdStartThreshold) {
        launchTime = time - UIApplicationInstantiateSingletonTime;
    }

    pthread_rwlock_unlock(&rwLock);
    return launchTime;
}
