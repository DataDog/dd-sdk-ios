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

- (void)testConfigurationWithNewApi {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100
                                                                                        textAndInputPrivacyLevel:DDTextAndInputPrivacyLevelMaskAll
                                                                                               imagePrivacyLevel:DDImagePrivacyLevelMaskNone
                                                                                               touchPrivacyLevel:DDTouchPrivacyLevelShow
                                                                                                    featureFlags:nil];
    configuration.customEndpoint = [NSURL new];

    configuration.textAndInputPrivacyLevel = DDTextAndInputPrivacyLevelMaskSensitiveInputs;
    configuration.imagePrivacyLevel = DDImagePrivacyLevelMaskAll;
    configuration.touchPrivacyLevel = DDTouchPrivacyLevelHide;

    [DDSessionReplay enableWith:configuration];
}

- (void)testStartAndStopRecording {
    [DDSessionReplay startRecording];
    [DDSessionReplay stopRecording];
}

- (void)testStartRecordingImmediately {
    DDSessionReplayConfiguration *configuration = [[DDSessionReplayConfiguration alloc] initWithReplaySampleRate:100
                                                                                        textAndInputPrivacyLevel:DDTextAndInputPrivacyLevelMaskAll
                                                                                               imagePrivacyLevel:DDImagePrivacyLevelMaskAll
                                                                                               touchPrivacyLevel:DDTouchPrivacyLevelHide
                                                                                                    featureFlags:nil];

    configuration.startRecordingImmediately = false;

    XCTAssertFalse(configuration.startRecordingImmediately);
}

// MARK: Privacy Overrides
- (void)testSettingAndGettingOverrides {
    // Given
    UIView *view = [[UIView alloc] init];

    // When
    view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayPrivacyOverrides.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayPrivacyOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayPrivacyOverrides.hide = @YES;

    // Then
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.imagePrivacy, DDImagePrivacyLevelOverrideMaskAll);
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.touchPrivacy, DDTouchPrivacyLevelOverrideHide);
    XCTAssertTrue(view.ddSessionReplayPrivacyOverrides.hide.boolValue);
}

- (void)testClearingOverride {
    // Given
    UIView *view = [[UIView alloc] init];

    // Set initial values
    view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideMaskAll;
    view.ddSessionReplayPrivacyOverrides.imagePrivacy = DDImagePrivacyLevelOverrideMaskAll;
    view.ddSessionReplayPrivacyOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideHide;
    view.ddSessionReplayPrivacyOverrides.hide = @YES;

    // When
    view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = DDTextAndInputPrivacyLevelOverrideNone;
    view.ddSessionReplayPrivacyOverrides.imagePrivacy = DDImagePrivacyLevelOverrideNone;
    view.ddSessionReplayPrivacyOverrides.touchPrivacy = DDTouchPrivacyLevelOverrideNone;
    view.ddSessionReplayPrivacyOverrides.hide = nil;

    // Then
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy, DDTextAndInputPrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.imagePrivacy, DDImagePrivacyLevelOverrideNone);
    XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.touchPrivacy, DDTouchPrivacyLevelOverrideNone);
    XCTAssertNil(view.ddSessionReplayPrivacyOverrides.hide);
}
@end
