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
        XCTAssertTrue(PrivacyLevel.allow.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(PrivacyLevel.mask.sensitiveTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(PrivacyLevel.maskUserInput.sensitiveTextObfuscator is FixLengthMaskObfuscator)
    }

    func testInputAndOptionTextObfuscation() {
        XCTAssertTrue(PrivacyLevel.allow.inputAndOptionTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(PrivacyLevel.mask.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(PrivacyLevel.maskUserInput.inputAndOptionTextObfuscator is FixLengthMaskObfuscator)
    }

    func testStaticTextObfuscation() {
        XCTAssertTrue(PrivacyLevel.allow.staticTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(PrivacyLevel.mask.staticTextObfuscator is SpacePreservingMaskObfuscator)
        XCTAssertTrue(PrivacyLevel.maskUserInput.staticTextObfuscator is NOPTextObfuscator)    }

    func testHintTextObfuscation() {
        XCTAssertTrue(PrivacyLevel.allow.hintTextObfuscator is NOPTextObfuscator)
        XCTAssertTrue(PrivacyLevel.mask.hintTextObfuscator is FixLengthMaskObfuscator)
        XCTAssertTrue(PrivacyLevel.maskUserInput.hintTextObfuscator is NOPTextObfuscator)
    }

    // MARK: - Convenience helpers

    func testShouldMaskInputElements() {
        XCTAssertFalse(PrivacyLevel.allow.shouldMaskInputElements)
        XCTAssertTrue(PrivacyLevel.mask.shouldMaskInputElements)
        XCTAssertTrue(PrivacyLevel.maskUserInput.shouldMaskInputElements)
    }
}
#endif
