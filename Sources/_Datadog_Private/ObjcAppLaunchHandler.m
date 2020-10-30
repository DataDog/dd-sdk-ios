/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

#import "ObjcAppLaunchHandler.h"

@implementation ObjcAppLaunchHandler: NSObject

static NSDate *_startTimeNS;

+ (void)load {
    // This is called at the `_Datadog_Private` load time, keep the work minimal
    _startTimeNS = [NSDate new];
}

+ (NSTimeInterval)measureTimeToNow {
    NSTimeInterval elapsedTime = [[NSDate new] timeIntervalSinceDate:_startTimeNS];
    return elapsedTime;
}

@end
