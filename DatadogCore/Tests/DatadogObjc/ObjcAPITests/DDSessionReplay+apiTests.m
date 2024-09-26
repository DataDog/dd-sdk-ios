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

// MARK: Overrides
- (void)testSettingAndGettingOverrides {
    // Given
    UIView *view = [[UIView alloc] init];
    DDSessionReplayOverride *override = [[DDSessionReplayOverride alloc] init];

    // When
    view.ddSessionReplayOverride = override;
    view.ddSessionReplayOverride.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverride.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverride.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayOverride.hide = @YES;

    // Then
    XCTAssertEqual(view.ddSessionReplayOverride.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayOverride.imagePrivacy, DDImagePrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayOverride.touchPrivacy, DDTouchPrivacyLevelOverrideHide);
    XCTAssertTrue(view.ddSessionReplayOverride.hide.boolValue);
}

- (void)testClearingOverride {
    // Given
    UIView *view = [[UIView alloc] init];
    DDSessionReplayOverride *override = [[DDSessionReplayOverride alloc] init];

    // Set initial values
    view.ddSessionReplayOverride = override;
    view.ddSessionReplayOverride.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverride.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayOverride.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayOverride.hide = @YES;

    // When
    view.ddSessionReplayOverride.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideNone;
    view.ddSessionReplayOverride.imagePrivacy = DDImagePrivacyLevelOverrideNone;
    view.ddSessionReplayOverride.touchPrivacy = DDTouchPrivacyLevelOverrideNone;
    view.ddSessionReplayOverride.hide = nil;

    // Then
    XCTAssertEqual(view.ddSessionReplayOverride.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayOverride.imagePrivacy, DDImagePrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayOverride.touchPrivacy, DDTouchPrivacyLevelOverrideNone);
    XCTAssertNil(view.ddSessionReplayOverride.hide);
}
@end
