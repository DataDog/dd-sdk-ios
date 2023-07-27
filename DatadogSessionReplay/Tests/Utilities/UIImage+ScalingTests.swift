/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
@testable import DatadogSessionReplay

class UIImageScalingTests: XCTestCase {
    func testScaledToApproximateSize_ReturnsOriginalImageData_IfSizeIsSmallerOrEqualToAnticipatedMaxSize() throws {
        let image: UIImage = .mockRandom(width: 50, height: 50)
        let pngData = try XCTUnwrap(image.pngData())
        let dataSize = pngData.count

        let maxSize = dataSize + 100
        let scaledData = image.scaledDownToApproximateSize(maxSize)
        XCTAssertEqual(scaledData, pngData)
    }

    func testScaledToApproximateSize_ScalesImageToSmallerSize_IfSizeIsLargerThanAnticipatedMaxSize() throws {
        let image: UIImage = .mockRandom(width: 50, height: 50)
        let pngData = try XCTUnwrap(image.pngData())
        let dataSize = pngData.count

        let maxSize = dataSize - 100
        let scaledData = image.scaledDownToApproximateSize(maxSize)
        XCTAssertTrue(scaledData.count < dataSize)
    }
}
