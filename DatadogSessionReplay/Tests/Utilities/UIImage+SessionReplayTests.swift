/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import XCTest

@testable import DatadogSessionReplay

class UIImageSessionReplayTests: XCTestCase {
    func testScaledToApproximateSize_ReturnsOriginalImageData_IfSizeIsSmallerOrEqualToAnticipatedMaxSize() throws {
        let image: UIImage = .mockRandom(width: 50, height: 50)
        let imageData = try XCTUnwrap(image.pngData())
        let scaledData = try XCTUnwrap(image.dd.pngData(maxSize: CGSize(width: 100, height: 100)))
        XCTAssertEqual(scaledData.count, imageData.count)
    }

    func testScaledToApproximateSize_ScalesImageToSmallerSize_IfSizeIsLargerThanAnticipatedMaxSize() throws {
        let image: UIImage = .mockRandom(width: 50, height: 50)
        let imageData = try XCTUnwrap(image.pngData())
        let scaledData = try XCTUnwrap(image.dd.pngData(maxSize: CGSize(width: 25, height: 25)))
        XCTAssertLessThan(scaledData.count, imageData.count)
    }
}

#endif
