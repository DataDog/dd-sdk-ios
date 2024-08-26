/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class PrivacyLevelTests: XCTestCase {
    // MARK: - Text obfuscation strategies

    func testSensitiveTextObfuscation() {
        XCTAssertTrue(TextAndInputPrivacyLevel.maskSensitiveInputs.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAllInputs.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAll.sensitiveTextObfuscator is FixLengthMaskObfuscator)
    }

    func testInputAndOptionTextObfuscation() {
        XCTAssertTrue(TextAndInputPrivacyLevel.maskSensitiveInputs.inputAndOptionTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAllInputs.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAll.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
    }

    func testStaticTextObfuscation() {
        XCTAssertTrue(TextAndInputPrivacyLevel.maskSensitiveInputs.staticTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAllInputs.staticTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAll.staticTextObfuscator is SpacePreservingMaskObfuscator)    }

    func testHintTextObfuscation() {
        XCTAssertTrue(TextAndInputPrivacyLevel.maskSensitiveInputs.hintTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAllInputs.hintTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAll.hintTextObfuscator is FixLengthMaskObfuscator)
    }

    // MARK: - Convenience helpers

    func testShouldMaskInputElements() {
        XCTAssertFalse(TextAndInputPrivacyLevel.maskSensitiveInputs.shouldMaskInputElements)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAllInputs.shouldMaskInputElements)
        XCTAssertTrue(TextAndInputPrivacyLevel.maskAll.shouldMaskInputElements)
    }
}
#endif
