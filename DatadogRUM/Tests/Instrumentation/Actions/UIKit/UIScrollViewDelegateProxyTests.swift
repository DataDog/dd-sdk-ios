/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import TestUtilities
@testable import DatadogRUM

class UIScrollViewDelegateProxyTests: XCTestCase {
    private let handler = MockScrollViewHandler()

    // MARK: - Forwarding Logic

    func testRespondsTo_whenOriginalDelegateResponds_itReturnsTrue() {
        // Given
        let originalDelegate = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(
            originalDelegate: originalDelegate,
            handler: handler
        )

        // When / Then
        XCTAssertTrue(proxy.responds(to: #selector(UIScrollViewDelegate.scrollViewDidScroll(_:))))
    }

    func testRespondsTo_whenOriginalDelegateDoesNotRespond_itReturnsFalse() {
        // Given
        let originalDelegate = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(
            originalDelegate: originalDelegate,
            handler: handler
        )

        // When / Then
        let arbitrarySelector = NSSelectorFromString("nonExistentMethod:")
        XCTAssertFalse(proxy.responds(to: arbitrarySelector))
    }

    func testRespondsTo_whenNoOriginalDelegate_itReturnsFalseForNonInterceptedMethods() {
        // Given
        let proxy = UIScrollViewDelegateProxy(
            originalDelegate: nil,
            handler: handler
        )

        // When / Then
        XCTAssertFalse(proxy.responds(to: #selector(UIScrollViewDelegate.scrollViewDidScroll(_:))))
    }

    func testForwardingTarget_returnsOriginalDelegateForUnhandledSelectors() {
        // Given
        let originalDelegate = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(
            originalDelegate: originalDelegate,
            handler: handler
        )

        // When
        let target = proxy.forwardingTarget(for: #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)))

        // Then
        XCTAssertTrue(target is MockScrollViewDelegate)
    }

    func testForwardingTarget_whenNoOriginalDelegate_itReturnsNil() {
        // Given
        let proxy = UIScrollViewDelegateProxy(
            originalDelegate: nil,
            handler: handler
        )

        // When
        let target = proxy.forwardingTarget(for: #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)))

        // Then
        XCTAssertNil(target)
    }
}

// MARK: - Test Mocks

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
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
    }
}

#endif
