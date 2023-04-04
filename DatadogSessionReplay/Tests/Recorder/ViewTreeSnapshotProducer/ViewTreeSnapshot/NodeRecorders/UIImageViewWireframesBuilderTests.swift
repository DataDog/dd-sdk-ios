/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
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
            image: UIImage(named: "dd_logo_v_rgb", in: Bundle.module, compatibleWith: nil),
            imageDataProvider: MockImageDataProvider(),
            tintColor: UIColor.mockRandom(),
            shouldRecordImage: true
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
            XCTAssertEqual(imageWireframe.base64, "mock_base64_string")
        } else {
            XCTFail("Second wireframe needs to be imageWireframe case")
        }
    }

    func test_BuildCorrectWireframes_whenContentImageIsIgnored() {
        let wireframeID = WireframeID.mockRandom()
        let imageWireframeID = WireframeID.mockRandom()
        let builder = UIImageViewWireframesBuilder(
            wireframeID: wireframeID,
            imageWireframeID: imageWireframeID,
            attributes: ViewAttributes.mock(fixture: .visible(.someAppearance)),
            contentFrame: CGRect(x: 10, y: 10, width: 200, height: 200),
            clipsToBounds: true,
            image: UIImage(named: "dd_logo_v_rgb", in: Bundle.module, compatibleWith: nil),
            imageDataProvider: mockRandomImageDataProvider(),
            tintColor: UIColor.mockRandom(),
            shouldRecordImage: false
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
            XCTAssertEqual(imageWireframe.base64, "")
        } else {
            XCTFail("Second wireframe needs to be imageWireframe case")
        }
    }
}
