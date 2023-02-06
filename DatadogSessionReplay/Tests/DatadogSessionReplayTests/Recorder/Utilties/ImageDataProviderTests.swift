/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class ImageDataProviderTests: XCTestCase {
    func test_returnsEmptyString_WhenContentIsEmpty() {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )

        let imageString = sut.contentBase64String(of: UIImageView())

        XCTAssertEqual(imageString, "")
    }

    func test_returnsValidString_WhenContentIsValid() throws {
        let sut = ImageDataProvider(
            queue: NoQueue()
        )
        let base64 = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="
        let image = UIImage(data: Data(base64Encoded: base64)!)

        XCTAssertNil(sut.contentBase64String(of: UIImageView(image: image)))
        let imageData = try XCTUnwrap(sut.contentBase64String(of: UIImageView(image: image)))
        XCTAssertGreaterThan(imageData.count, 0)
    }
}
