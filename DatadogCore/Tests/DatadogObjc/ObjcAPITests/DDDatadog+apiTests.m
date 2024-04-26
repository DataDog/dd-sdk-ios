/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogObjc;

@interface DDDatadog_apiTests : XCTestCase
@end

/*
 * `DatadogObjc` APIs smoke tests - only check if the interface is available to Objc.
 */
@implementation DDDatadog_apiTests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

- (void)testDDTrackingConsentAPI {
    [DDTrackingConsent granted];
    [DDTrackingConsent notGranted];
    [DDTrackingConsent pending];
}

- (void)testDDDatadog {
    DDConfiguration *configuration = [[DDConfiguration alloc] initWithClientToken:@"abc" env:@"def"];

    [DDDatadog initializeWithConfiguration:configuration trackingConsent:[DDTrackingConsent notGranted]];

    DDSDKVerbosityLevel verbosity = [DDDatadog verbosityLevel];
    [DDDatadog setVerbosityLevel:verbosity];

    [DDDatadog setUserInfoWithId:@"" name:@"" email:@"" extraInfo:@{}];
    [DDDatadog addUserExtraInfo:@{}];
    [DDDatadog setTrackingConsentWithConsent:[DDTrackingConsent notGranted]];

    [DDDatadog clearAllData];
    [DDDatadog flushAndDeinitialize];
}

#pragma clang diagnostic pop

@end
