/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import "ObjcOSActivityUtils.h"

@implementation ObjcOSActivityUtils

+ (os_activity_t) currentActivity {
    @synchronized(self) {
        return OS_ACTIVITY_CURRENT;
    }
}

@end
