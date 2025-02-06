/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <pthread.h>
#import <sys/sysctl.h>

#import "ObjcAppLaunchHandler.h"

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

// A very long application launch time is most-likely the result of a pre-warmed process.
// We consider 30s as a threshold for pre-warm detection.
#define COLD_START_TIME_THRESHOLD 30

/// Get the process start time from kernel.
///
/// The time interval is relative to the 1 January 2001 00:00:00 GMT reference date.
///
/// - Parameter timeInterval: Pointer to time interval to hold the process start time interval.
int processStartTimeIntervalSinceReferenceDate(NSTimeInterval *timeInterval);

/// Tracks key timestamps in the app launch sequence
/// ref. https://developer.apple.com/documentation/uikit/app_and_environment/responding_to_the_launch_of_your_app/about_the_app_launch_sequence
@implementation __dd_private_AppLaunchHandler {
    NSTimeInterval _processStartTime;
    NSTimeInterval _timeToApplicationDidBecomeActive;
    BOOL _isActivePrewarm;
    UIApplicationDidBecomeActiveCallback _applicationDidBecomeActiveCallback;
}

/// Shared instance of the Application Launch Handler.
static __dd_private_AppLaunchHandler *_shared;

+ (void)load {
    // This is called at the `DatadogPrivate` load time, keep the work minimal
    _shared = [self createWithProcessInfo:NSProcessInfo.processInfo
                      notificationCenter:NSNotificationCenter.defaultCenter];
}

+ (instancetype)createWithProcessInfo:(NSProcessInfo *)processInfo
                   notificationCenter:(NSNotificationCenter *)notificationCenter
{
    __dd_private_AppLaunchHandler *handler = [[self alloc] initWithProcessInfo:processInfo];

    NSString *notificationName;
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_MACCATALYST || TARGET_OS_VISION
    notificationName = UIApplicationDidBecomeActiveNotification;
#elif TARGET_OS_OSX
    notificationName = NSApplicationDidBecomeActiveNotification;
#endif

    if (notificationName && notificationCenter) {
        __weak NSNotificationCenter *weakCenter = notificationCenter;
        __block id __unused token = [notificationCenter addObserverForName:notificationName
                                                                     object:nil
                                                                      queue:NSOperationQueue.mainQueue
                                                                 usingBlock:^(NSNotification *_){
            @synchronized(handler) {
                NSTimeInterval time = CFAbsoluteTimeGetCurrent() - handler->_processStartTime;
                handler->_timeToApplicationDidBecomeActive = time;
                handler->_applicationDidBecomeActiveCallback(time);
            }

            [weakCenter removeObserver:token];
            token = nil;
        }];
    }

    return handler;
}

+ (__dd_private_AppLaunchHandler *)shared {
    return _shared;
}

- (instancetype)initWithProcessInfo:(NSProcessInfo *)processInfo {
    NSTimeInterval startTime;
    if (processStartTimeIntervalSinceReferenceDate(&startTime) != 0) {
        // Fall back to "now"
        startTime = CFAbsoluteTimeGetCurrent();
    }

    // The ActivePrewarm variable indicates whether the app was launched via pre-warming.
    BOOL isActivePrewarm = [processInfo.environment[@"ActivePrewarm"] isEqualToString:@"1"];
    return [self initWithStartTime:startTime isActivePrewarm:isActivePrewarm];
}

- (instancetype)initWithStartTime:(NSTimeInterval)startTime isActivePrewarm:(BOOL)isActivePrewarm {
    self = [super init];
    if (!self) return nil;
    _processStartTime = startTime;
    _isActivePrewarm = isActivePrewarm;
    _applicationDidBecomeActiveCallback = ^(NSTimeInterval _) {};
    return self;
}

- (NSDate *)launchDate {
    @synchronized(self) {
        return [NSDate dateWithTimeIntervalSinceReferenceDate:_processStartTime];
    }
}

- (NSNumber *)launchTime {
    @synchronized(self) {
        return _timeToApplicationDidBecomeActive > 0 ? @(_timeToApplicationDidBecomeActive) : nil;
    }
}

- (BOOL)isActivePrewarm {
    @synchronized(self) {
        if (_isActivePrewarm) return _isActivePrewarm;
        return _timeToApplicationDidBecomeActive > COLD_START_TIME_THRESHOLD;
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
