/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class ImageDataProviderTests: XCTestCase {
    func test_returnsNil_WhenImageIsNil() {
        let sut = ImageDataProvider()

        XCTAssertNil(sut.contentBase64String(of: nil))
    }

    func test_returnsEmptyStringAndIdentifier_WhenContentIsEmpty() {
        let sut = ImageDataProvider()
        let imageResource = sut.contentBase64String(of: UIImage())

        XCTAssertEqual(imageResource?.base64, "")
        XCTAssertEqual(imageResource?.identifier, "")
    }

    func test_returnsValidStringAndIdentifier_WhenContentIsValid() throws {
        let sut = ImageDataProvider()
        let base64 = "R0lGODlhAQABAIAAAP7//wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw=="
        let image = UIImage(data: Data(base64Encoded: base64)!)

        let imageResource = try XCTUnwrap(sut.contentBase64String(of: image))
        XCTAssertGreaterThan(imageResource.base64.count, 0)
        XCTAssertEqual(imageResource.identifier, "258d046955bfb950883f0ed61b586b5a")
    }

    @available(iOS 13.0, *)
    func test_returnsValidStringAndIdentifier_forSFSymbolIcon() throws {
        let sut = ImageDataProvider()
        let image = UIImage(systemName: "square.and.arrow.up")

        let imageResource = try XCTUnwrap(sut.contentBase64String(of: image))
        XCTAssertGreaterThan(imageResource.base64.count, 0)
        XCTAssertEqual(imageResource.identifier, "89187ac6043b08c088090d348fbb397f")
    }

    func test_imageIdentifierConsistency() {
        var ids = Set<String>()
        let image: UIImage = .mockRandom()
        for _ in 0..<100 {
            ids.insert(image.srIdentifier)
        }
        XCTAssertEqual(ids.count, 1)
    }

    func test_colorIdentifierConsistency() {
        var ids = Set<String>()
        for _ in 0..<100 {
            ids.insert( UIColor.red.srIdentifier)
        }
        XCTAssertEqual(ids.count, 1)
    }
}
