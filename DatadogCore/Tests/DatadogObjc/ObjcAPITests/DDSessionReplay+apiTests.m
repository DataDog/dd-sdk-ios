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

// MARK: Configuration
- (void)testConfiguration {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100];
    configuration.defaultPrivacyLevel = DDSessionReplayConfigurationPrivacyLevelAllow;
    configuration.customEndpoint = [NSURL new];

    [DDSessionReplay enableWith:configuration];
}

- (void)testConfigurationWithNewApi {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100
                                                   textAndInputPrivacyLevel:DDTextAndInputPrivacyLevelMaskAll
                                                   imagePrivacyLevel:DDImagePrivacyLevelMaskNone
                                                   touchPrivacyLevel:DDTouchPrivacyLevelShow];
    configuration.customEndpoint = [NSURL new];

    [DDSessionReplay enableWith:configuration];
}

- (void)testStartAndStopRecording {
    [DDSessionReplay startRecording];
    [DDSessionReplay stopRecording];
}

// MARK: Privacy Overrides
- (void)testSettingAndGettingOverrides {
    // Given
    UIView *view = [[UIView alloc] init];
    DDSessionReplayOverrides *override = [[DDSessionReplayOverrides alloc] init];

    // When
    view.ddSessionReplayOverrides = override;
    view.ddSessionReplayOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverrides.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayOverrides.hide = @YES;

    // Then
    XCTAssertEqual(view.ddSessionReplayOverrides.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayOverrides.imagePrivacy, DDImagePrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayOverrides.touchPrivacy, DDTouchPrivacyLevelOverrideHide);
    XCTAssertTrue(view.ddSessionReplayOverrides.hide.boolValue);
}

- (void)testClearingOverride {
    // Given
    UIView *view = [[UIView alloc] init];
    DDSessionReplayOverrides *overrides = [[DDSessionReplayOverrides alloc] init];

    // Set initial values
    view.ddSessionReplayOverrides = overrides;
    view.ddSessionReplayOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverrides.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayOverrides.hide = @YES;

    // When
    view.ddSessionReplayOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideNone;
    view.ddSessionReplayOverrides.imagePrivacy = DDImagePrivacyLevelOverrideNone;
    view.ddSessionReplayOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideNone;
    view.ddSessionReplayOverrides.hide = nil;

    // Then
    XCTAssertEqual(view.ddSessionReplayOverrides.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayOverrides.imagePrivacy, DDImagePrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayOverrides.touchPrivacy, DDTouchPrivacyLevelOverrideNone);
    XCTAssertNil(view.ddSessionReplayOverrides.hide);
}
@end
