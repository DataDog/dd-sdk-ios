/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest

@testable import DatadogSessionReplay

final class CALayerSwizzlerTests: XCTestCase {
    private let layerObserverMock = CALayerObserverMock()
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var layerSwizzler: CALayerSwizzler!

    override func setUp() async throws {
        try await super.setUp()
        layerSwizzler = try CALayerSwizzler(observer: layerObserverMock)
        layerSwizzler.swizzle()
    }

    override func tearDown() {
        layerSwizzler.unswizzle()
        super.tearDown()
    }

    func testObserveLayerDisplay() {
        // given
        let layer = CALayer()

        // when
        layer.display()

        // then
        XCTAssertEqual(layerObserverMock.layerDidDisplayCalls.count, 1)
        XCTAssertIdentical(layerObserverMock.layerDidDisplayCalls.first, layer)
    }

    func testObserveLayerDraw() {
        // given
        let layer = CALayer()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // when
        layer.draw(in: context)

        // then
        XCTAssertEqual(layerObserverMock.layerDidDrawCalls.count, 1)
        XCTAssertIdentical(layerObserverMock.layerDidDrawCalls.first?.layer, layer)
        XCTAssertIdentical(layerObserverMock.layerDidDrawCalls.first?.context, context)
    }

    func testObserveLayerLayoutSublayers() {
        // given
        let layer = CALayer()

        // when
        layer.layoutSublayers()

        // then
        XCTAssertEqual(layerObserverMock.layerDidLayoutSublayersCalls.count, 1)
        XCTAssertIdentical(layerObserverMock.layerDidLayoutSublayersCalls.first, layer)
    }
}
#endif
