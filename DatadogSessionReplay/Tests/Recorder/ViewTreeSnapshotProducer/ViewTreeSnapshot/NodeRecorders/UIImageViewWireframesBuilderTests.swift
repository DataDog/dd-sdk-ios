/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UIImageViewWireframesBuilderTests: XCTestCase {
    var wireframesBuilder: WireframesBuilder = .init()

    override func setUp() {
        super.setUp()
        wireframesBuilder = WireframesBuilder()
    }

    func test_BuildCorrectWireframes_fromValidData() {
        let wireframeID = WireframeID.mockRandom()
        let imageWireframeID = WireframeID.mockRandom()
        let builder = UIImageViewWireframesBuilder(
            wireframeID: wireframeID,
            imageWireframeID: imageWireframeID,
            attributes: ViewAttributes.mock(fixture: .visible(.someAppearance)),
            contentFrame: CGRect(x: 10, y: 10, width: 200, height: 200),
            clipsToBounds: true,
            imageResource: .mockRandom(),
            imagePrivacyLevel: .maskNonBundledOnly
        )

        let wireframes = builder.buildWireframes(with: wireframesBuilder)

        XCTAssertEqual(wireframes.count, 2)

        if case let .shapeWireframe(shapeWireframe) = wireframes[0] {
            XCTAssertEqual(shapeWireframe.id, wireframeID)
        } else {
            XCTFail("First wireframe needs to be shapeWireframe case")
        }

        if case let .imageWireframe(imageWireframe) = wireframes[1] {
            XCTAssertEqual(imageWireframe.id, imageWireframeID)
            XCTAssertNil(imageWireframe.base64) // deprecated field
        } else {
            XCTFail("Second wireframe needs to be imageWireframe case")
        }
    }

    func test_BuildCorrectWireframes_whenContentImageIsIgnored() {
        let wireframeID = WireframeID.mockRandom()
        let placeholderWireframeID = WireframeID.mockRandom()
        let builder = UIImageViewWireframesBuilder(
            wireframeID: wireframeID,
            imageWireframeID: placeholderWireframeID,
            attributes: ViewAttributes.mock(fixture: .visible(.someAppearance)),
            contentFrame: CGRect(x: 10, y: 10, width: 200, height: 200),
            clipsToBounds: true,
            imageResource: nil,
            imagePrivacyLevel: .maskNonBundledOnly
        )

        let wireframes = builder.buildWireframes(with: wireframesBuilder)

        XCTAssertEqual(wireframes.count, 2)

        if case let .shapeWireframe(shapeWireframe) = wireframes[0] {
            XCTAssertEqual(shapeWireframe.id, wireframeID)
        } else {
            XCTFail("First wireframe needs to be shapeWireframe case")
        }

        if case let .placeholderWireframe(placeholderWireframe) = wireframes[1] {
            XCTAssertEqual(placeholderWireframe.id, placeholderWireframeID)
            XCTAssertEqual(placeholderWireframe.label, "Content Image")
        } else {
            XCTFail("Second wireframe needs to be imageWireframe case")
        }
    }
}
#endif
