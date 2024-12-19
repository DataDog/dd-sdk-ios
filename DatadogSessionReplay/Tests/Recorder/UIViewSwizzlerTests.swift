/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay

final class UIViewSwizzlerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var swizzler: UIViewSwizzler!
    private var mockHandler: MockUIViewHandler!
    private var testView: UIView!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockHandler = MockUIViewHandler()
        swizzler = try UIViewSwizzler(handler: mockHandler)
        testView = UIView()
    }

    override func tearDownWithError() throws {
        swizzler.unswizzle()
        swizzler = nil
        mockHandler = nil
        testView = nil
        try super.tearDownWithError()
    }

    func testLayoutSubviewsSwizzling() throws {
        swizzler.swizzle()

        testView.layoutSubviews()

        XCTAssertTrue(mockHandler.layoutSubviewsCalled, "Expected layoutSubviews to notify handler")
        XCTAssertEqual(mockHandler.notifiedView, testView, "Expected layoutSubviews to pass the correct view")
    }

    func testUnswizzling() throws {
        swizzler.swizzle()
        swizzler.unswizzle()

        mockHandler.layoutSubviewsCalled = false
        mockHandler.notifiedView = nil

        testView.layoutSubviews()

        XCTAssertFalse(mockHandler.layoutSubviewsCalled, "Handler should not be called after unswizzling layoutSubviews")
        XCTAssertNil(mockHandler.notifiedView, "Handler should not receive a view after unswizzling")
    }
}

class MockUIViewHandler: UIViewHandler {
    var layoutSubviewsCalled = false
    var notifiedView: UIView?

    func notify_layoutSubviews(view: UIView) {
        layoutSubviewsCalled = true
        notifiedView = view
    }
}
#endif
