/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import <UIKit/UIKit.h>
#import "ObjcAppLaunchHandler.h"

@interface AppLaunchTimer : NSObject
@property NSDate *frameworkLoadTime;
// Knowing how this value is collected and that it is written only once, the use of
// `atomic` property is enough for thread safety. It guarantees that neither partial
// nor garbage value will be returned.
@property (atomic) NSTimeInterval timeToApplicationBecomeActive;
@end

@implementation AppLaunchTimer

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSDate *time = [NSDate new];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleDidBecomeActiveNotification)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil
         ];
        self.frameworkLoadTime = time;
        self.timeToApplicationBecomeActive = 0;
    }
    return self;
}

- (void)handleDidBecomeActiveNotification {
    NSDate *time = [NSDate new];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.timeToApplicationBecomeActive = [time timeIntervalSinceDate:self.frameworkLoadTime];
}

@end


@implementation ObjcAppLaunchHandler: NSObject

static AppLaunchTimer *_timer;

+ (void)load {
    // This is called at the `_Datadog_Private` load time, keep the work minimal
    _timer = [AppLaunchTimer new];
}

+ (NSTimeInterval)launchTime {
    return _timer.timeToApplicationBecomeActive;
}

@end
