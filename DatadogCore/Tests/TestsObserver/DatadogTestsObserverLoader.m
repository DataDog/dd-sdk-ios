/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if TARGET_OS_IOS
#import "DatadogCoreTests_iOS-Swift.h"
#elif TARGET_OS_TV
#import "DatadogCoreTests_tvOS-Swift.h"
#endif

/// This code runs when the `DatadogTests` bundle is loaded into memory and tests start.
/// Reference: https://developer.apple.com/documentation/objectivec/nsobject/1418815-load
__attribute__((constructor)) static void initialize_FrameworkLoadHandler(void) {
    [DatadogTestsObserver startObserving];
}
