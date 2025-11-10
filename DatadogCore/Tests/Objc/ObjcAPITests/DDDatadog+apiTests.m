/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

#import <XCTest/XCTest.h>
@import DatadogCore;
@import DatadogInternal;

@interface DDDatadog_apiTests : XCTestCase
@end

/*
 * Objc APIs smoke tests - only check if the interface is available to Objc.
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

    [DDDatadog isInitialized];

    DDCoreLoggerLevel verbosity = [DDDatadog verbosityLevel];
    [DDDatadog setVerbosityLevel:verbosity];

    [DDDatadog setUserInfoWithUserId:@"" name:@"" email:@"" extraInfo:@{}];
    [DDDatadog currentUserId];
    [DDDatadog addUserExtraInfo:@{}];
    [DDDatadog currentAccountId];
    [DDDatadog setTrackingConsentWithConsent:[DDTrackingConsent notGranted]];

    [DDDatadog clearAllData];
    [DDDatadog stopInstance];
}

#pragma clang diagnostic pop

@end
