/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class SessionReplayPrivacyTests: XCTestCase {
    // MARK: - Text obfuscation strategies

    func testSensitiveTextObfuscation() {
        XCTAssertTrue(SessionReplayPrivacy.allowAll.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskAll.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskUserInput.sensitiveTextObfuscator is FixLengthMaskObfuscator)
    }

    func testInputAndOptionTextObfuscation() {
        XCTAssertTrue(SessionReplayPrivacy.allowAll.inputAndOptionTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskAll.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskUserInput.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
    }

    func testStaticTextObfuscation() {
        XCTAssertTrue(SessionReplayPrivacy.allowAll.staticTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskAll.staticTextObfuscator is SpacePreservingMaskObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskUserInput.staticTextObfuscator is NOPTextObfuscator)    }

    func testHintTextObfuscation() {
        XCTAssertTrue(SessionReplayPrivacy.allowAll.hintTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskAll.hintTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(SessionReplayPrivacy.maskUserInput.hintTextObfuscator is NOPTextObfuscator)
    }

    // MARK: - Convenience helpers

    func testShouldMaskInputElements() {
        XCTAssertFalse(SessionReplayPrivacy.allowAll.shouldMaskInputElements)
        XCTAssertTrue(SessionReplayPrivacy.maskAll.shouldMaskInputElements)
        XCTAssertTrue(SessionReplayPrivacy.maskUserInput.shouldMaskInputElements)
    }
}
