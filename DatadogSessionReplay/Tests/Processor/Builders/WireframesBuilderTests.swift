/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

class WireframesBuilderTests: XCTestCase {
    func testBuildingVisibleWebVieWireframes_ItRemovesSlotFromCache() {
        let slots: Set<Int> = .mockRandom(count: 10)
        let builder = WireframesBuilder(webViewSlotIDs: slots)

        slots.forEach { id in
            let frame: CGRect = .mockRandom()
            let wireframe = builder.visibleWebViewWireframe(id: id, frame: frame)
            guard case let .webviewWireframe(wireframe) = wireframe else {
                return XCTFail("The wireframe must be webviewWireframe case")
            }

            XCTAssertEqual(wireframe.id, Int64(id))
            XCTAssertEqual(wireframe.slotId, String(id))
            XCTAssertTrue(wireframe.isVisible ?? false)
            XCTAssertNil(wireframe.border)
            XCTAssertNil(wireframe.clip)
            XCTAssertEqual(wireframe.height, Int64(withNoOverflow: frame.height))
            XCTAssertNil(wireframe.shapeStyle)
            XCTAssertEqual(wireframe.width, Int64(withNoOverflow: frame.size.width))
            XCTAssertEqual(wireframe.x, Int64(withNoOverflow: frame.minX))
            XCTAssertEqual(wireframe.y, Int64(withNoOverflow: frame.minY))
        }

        XCTAssertTrue(builder.hiddenWebViewWireframes().isEmpty)
    }

    func testBuildingHiddenWebVieWireframes_ItRemovesSlotFromCache() {
        let slots: Set<Int> = .mockRandom(count: 10)
        let builder = WireframesBuilder(webViewSlotIDs: slots)

        builder.hiddenWebViewWireframes().forEach { wireframe in
            guard case let .webviewWireframe(wireframe) = wireframe else {
                return XCTFail("The wireframe must be webviewWireframe case")
            }

            XCTAssertEqual(String(wireframe.id), wireframe.slotId)
            XCTAssertFalse(wireframe.isVisible ?? true)
            XCTAssertNil(wireframe.border)
            XCTAssertNil(wireframe.clip)
            XCTAssertEqual(wireframe.height, 0)
            XCTAssertNil(wireframe.shapeStyle)
            XCTAssertEqual(wireframe.width, 0)
            XCTAssertEqual(wireframe.x, 0)
            XCTAssertEqual(wireframe.y, 0)
        }

        XCTAssertTrue(builder.hiddenWebViewWireframes().isEmpty)
    }
}
#endif
