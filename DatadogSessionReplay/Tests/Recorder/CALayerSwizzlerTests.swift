/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

final class CALayerSwizzlerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var swizzler: CALayerSwizzler!
    private var mockHandler: MockCALayerHandler!
    private var testLayer: CALayer!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockHandler = MockCALayerHandler()
        swizzler = try CALayerSwizzler(handler: mockHandler)
        testLayer = CALayer()
    }

    override func tearDownWithError() throws {
        swizzler.unswizzle()
        swizzler = nil
        mockHandler = nil
        testLayer = nil
        try super.tearDownWithError()
    }

    func testSetNeedsDisplaySwizzling() throws {
        swizzler.swizzle()

        testLayer.setNeedsDisplay()

        XCTAssertTrue(mockHandler.setNeedsDisplayCalled, "Expected setNeedsDisplay to notify handler")
    }

    func testDrawSwizzling() throws {
        swizzler.swizzle()

        UIGraphicsBeginImageContext(CGSize(width: 100, height: 100))
        guard let context = UIGraphicsGetCurrentContext() else {
            XCTFail("Failed to create CGContext")
            return
        }

        testLayer.draw(in: context)

        XCTAssertTrue(mockHandler.drawCalled, "Expected draw(in:) to notify handler")
        XCTAssertEqual(mockHandler.drawnLayer, testLayer, "Expected draw(in:) to pass the correct layer")
        XCTAssertEqual(mockHandler.drawnContext, context, "Expected draw(in:) to pass the correct context")

        UIGraphicsEndImageContext()
    }

    func testUnswizzling() throws {
        swizzler.swizzle()
        swizzler.unswizzle()

        testLayer.setNeedsDisplay()

        UIGraphicsBeginImageContext(CGSize(width: 100, height: 100))
        guard let context = UIGraphicsGetCurrentContext() else {
            XCTFail("Failed to create CGContext")
            return
        }

        testLayer.draw(in: context)
        UIGraphicsEndImageContext()

        XCTAssertFalse(mockHandler.setNeedsDisplayCalled, "Handler should not be called after unswizzling setNeedsDisplay")
        XCTAssertFalse(mockHandler.drawCalled, "Handler should not be called after unswizzling draw(in:)")
    }
}

class MockCALayerHandler: CALayerHandler {
    var setNeedsDisplayCalled = false
    var drawCalled = false
    var drawnLayer: CALayer?
    var drawnContext: CGContext?

    func notify_setNeedsDisplay(layer: CALayer) {
        setNeedsDisplayCalled = true
    }

    func notify_draw(layer: CALayer, context: CGContext) {
        drawCalled = true
        drawnLayer = layer
        drawnContext = context
    }
}
#endif
