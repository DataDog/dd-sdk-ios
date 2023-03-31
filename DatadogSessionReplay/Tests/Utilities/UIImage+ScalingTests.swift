/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
class UIImageScalingTests: XCTestCase {
    var sut: (image: UIImage, pngData: Data) {
        guard let image = UIImage(named: "dd_logo_v_rgb", in: Bundle.module, compatibleWith: nil), let imageData = image.pngData() else {
            XCTFail("Failed to load image")
            return (UIImage(), Data())
        }
        return (image, imageData)
    }

    func testScaledToApproximateSize_ReturnsOriginalImageData_IfSizeIsSmallerOrEqualToAnticipatedMaxSize() {
        let dataSize = sut.pngData.count
        let maxSize = dataSize + 100
        let scaledData = sut.image.scaledDownToApproximateSize(maxSize)
        XCTAssertEqual(scaledData, sut.pngData)
    }

    func testScaledToApproximateSize_ScalesImageToSmallerSize_IfSizeIsLargerThanAnticipatedMaxSize() {
        let dataSize = sut.pngData.count
        let maxSize = dataSize - 100
        let scaledData = sut.image.scaledDownToApproximateSize(maxSize)
        XCTAssertTrue(scaledData.count < dataSize)
    }
}
