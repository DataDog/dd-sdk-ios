/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "ObjcAppLaunchHandler.h"
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>
#import <pthread.h>

// `AppLaunchHandler` aims to track some times as part of the sequence described in Apple's "About the App Launch Sequence"
// https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence

// A Read-Write lock to allow concurrent reads of TimeToApplicationDidBecomeActive, unless the initial (and only) write is locking it.
static pthread_rwlock_t rwLock;
static NSTimeInterval TimeToApplicationDidBecomeActive = 0.0;

NS_INLINE NSTimeInterval QueryProcessStartTimeWithFallback(NSTimeInterval fallbackTime) {
    NSTimeInterval processStartTime;
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
        processStartTime = startTime.tv_sec + startTime.tv_usec / USEC_PER_SEC;
        // Convert to time since 1 Jan 2001 to align with CFAbsoluteTimeGetCurrent()
        processStartTime -= kCFAbsoluteTimeIntervalSince1970;
    } else {
        // Fallback to less accurate delta with DD's framework load time
        processStartTime = fallbackTime;
    }
    return processStartTime;
}

NS_INLINE void ComputeTimeToApplicationDidBecomeActiveWithFallback(NSTimeInterval fallbackTime) {
    if (TimeToApplicationDidBecomeActive > 0) {
        return;
    }

    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval processStartTime = QueryProcessStartTimeWithFallback(fallbackTime);
    TimeToApplicationDidBecomeActive = now - processStartTime;
}

@interface AppLaunchHandler : NSObject
@end

@implementation AppLaunchHandler

+ (void)load {
    // This is called at the `_Datadog_Private` load time, keep the work minimal
    NSTimeInterval frameworkLoadTime = CFAbsoluteTimeGetCurrent();
    id __block token = [NSNotificationCenter.defaultCenter
                        addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                        queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *_){

        pthread_rwlock_init(&rwLock, NULL);
        pthread_rwlock_wrlock(&rwLock);
        ComputeTimeToApplicationDidBecomeActiveWithFallback(frameworkLoadTime);
        pthread_rwlock_unlock(&rwLock);

        [NSNotificationCenter.defaultCenter removeObserver:token];
    }];
}

@end

CFTimeInterval __dd_private_AppLaunchTime() {
    pthread_rwlock_rdlock(&rwLock);
    CFTimeInterval time = TimeToApplicationDidBecomeActive;
    pthread_rwlock_unlock(&rwLock);
    return time;
}
