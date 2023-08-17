/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <XCTest/XCTest.h>

#if TARGET_OS_IOS

@import DatadogObjc;

@interface DDSessionReplay_apiTests : XCTestCase
@end

@implementation DDSessionReplay_apiTests

- (void)testConfiguration {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100];
    configuration.defaultPrivacyLevel = DDSessionReplayConfigurationPrivacyLevelAllow;
    configuration.customEndpoint = [NSURL new];

    [DDSessionReplay enableWith:configuration];
}

@end

#endif
