//
//  ObjcOSActivityUtils.m
//  Datadog
//
//  Created by Ignacio Bonafonte Arruga on 03/08/2020.
//  Copyright © 2020 Datadog. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ObjcOSActivityUtils.h"

@implementation ObjcOSActivityUtils

static os_activity_t _currentActivity = OS_ACTIVITY_CURRENT;

+ (os_activity_t) currentActivity {
    return _currentActivity;
}

@end
