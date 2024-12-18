/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class ImagePrivacyTests: XCTestCase {
    func testShouldRecordImagePredicate() {
        // Given
        let smallImage = MockCGImage.mockWith(width: 20)
        let smallGraphicsImage = GraphicsImage(contents: .cgImage(smallImage), scale: 1.0, orientation: .up)

        // Then
        XCTAssertTrue(ImagePrivacyLevel.maskNone.shouldRecordGraphicsImagePredicate(smallGraphicsImage))
        XCTAssertFalse(ImagePrivacyLevel.maskAll.shouldRecordGraphicsImagePredicate(smallGraphicsImage))
        XCTAssertTrue(ImagePrivacyLevel.maskNonBundledOnly.shouldRecordGraphicsImagePredicate(smallGraphicsImage))

        // Given
        let largeImage = MockCGImage.mockWith(width: 150)
        let largeGraphicsImage = GraphicsImage(contents: .cgImage(largeImage), scale: 1.0, orientation: .up)

        // Then
        XCTAssertTrue(ImagePrivacyLevel.maskNone.shouldRecordGraphicsImagePredicate(largeGraphicsImage))
        XCTAssertFalse(ImagePrivacyLevel.maskAll.shouldRecordGraphicsImagePredicate(largeGraphicsImage))
        XCTAssertFalse(ImagePrivacyLevel.maskNonBundledOnly.shouldRecordGraphicsImagePredicate(largeGraphicsImage))
    }
}
#endif
