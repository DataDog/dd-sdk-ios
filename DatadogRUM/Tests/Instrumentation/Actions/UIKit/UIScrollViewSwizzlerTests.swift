/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import TestUtilities
@testable import DatadogRUM

@MainActor
class UIScrollViewSwizzlerTests: XCTestCase {
    private var handler: MockScrollViewHandler?
    private var swizzler: UIScrollViewSwizzler?

    override func setUp() {
        super.setUp()
        handler = MockScrollViewHandler()
    }

    override func tearDown() {
        swizzler?.unswizzle()
        swizzler = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Swizzling

    func testSwizzle_interceptsDelegateSetterAndCreatesProxy() throws {
        // Given
        guard let handler = handler else {
            XCTFail("Handler should be initialized")
            return
        }
        swizzler = try UIScrollViewSwizzler(handler: handler)
        let scrollView = UIScrollView()
        let delegate = MockScrollViewDelegate()

        // When
        swizzler?.swizzle()
        scrollView.delegate = delegate

        // Then - delegate is wrapped in a proxy
        XCTAssertTrue(scrollView.delegate is UIScrollViewDelegateProxy)
    }

    // MARK: - Double-Wrap Prevention

    func testDoubleWrapPrevention_whenDelegateIsAlreadyProxy_itDoesNotWrapAgain() throws {
        // Given
        guard let handler = handler else {
            XCTFail("Handler should be initialized")
            return
        }
        swizzler = try UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()

        let scrollView = UIScrollView()
        let delegate = MockScrollViewDelegate()

        // When - set delegate twice
        scrollView.delegate = delegate
        let firstProxy = scrollView.delegate
        scrollView.delegate = firstProxy // Set proxy as delegate

        // Then - should not create nested proxies
        XCTAssertTrue(scrollView.delegate is UIScrollViewDelegateProxy)
        XCTAssertTrue(scrollView.delegate === firstProxy) // Same proxy instance
    }
}

// MARK: - Test Mocks

@MainActor
private class MockScrollViewHandler: UIScrollViewHandler {
    func notify_scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    }

    func notify_scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    }

    func notify_scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    }

    func publish(to subscriber: RUMCommandSubscriber) {
    }
}

private class MockScrollViewDelegate: NSObject, UIScrollViewDelegate {
}

#endif
