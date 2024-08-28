/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#import <XCTest/XCTest.h>

@import DatadogSessionReplay;

@interface DDSessionReplay_apiTests : XCTestCase
@end

@implementation DDSessionReplay_apiTests

- (void)testConfiguration {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100];
    configuration.defaultPrivacyLevel = DDSessionReplayConfigurationPrivacyLevelAllow;
    configuration.customEndpoint = [NSURL new];

    [DDSessionReplay enableWith:configuration];
}

- (void)testConfigurationWithNewApi {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100
                                                                                        textAndInputPrivacyLevel:DDSessionReplayConfigurationTextAndInputPrivacyLevelMaskAll
                                                                                               imagePrivacyLevel:DDImagePrivacyLevelMaskNone
                                                                                               touchPrivacyLevel:DDTouchPrivacyLevelShow];

    configuration.textAndInputPrivacyLevel = DDSessionReplayConfigurationTextAndInputPrivacyLevelMaskSensitiveInputs;
    configuration.imagePrivacyLevel = DDImagePrivacyLevelMaskAll;
    configuration.touchPrivacyLevel = DDTouchPrivacyLevelHide;
    configuration.customEndpoint = [NSURL new];

    [DDSessionReplay enableWith:configuration];
}

@end
