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

    // MARK: - Proxy lifetime (regression for SwiftUI UICollectionView crash)

    func testProxyLifetime_whenOriginalDelegateIsDeallocated_doesNotCrashOnSubsequentDelegateCall() {
        // Regression test for: https://github.com/DataDog/dd-sdk-ios/issues/2760
        //
        // Expected behavior: the proxy's lifetime must be tied to the original delegate's lifetime.
        // When the delegate is deallocated, the proxy must be released too, so that
        // scrollView.delegate (a weak reference) becomes nil and UIKit stops dispatching to it.
        //
        // Failure mode without the fix: the proxy is owned by the scroll view (associated object),
        // so it outlives the delegate. UIKit caches responds(to:) == true for selectors the proxy
        // advertised via the delegate, then dispatches them directly to the proxy. With originalDelegate
        // gone, forwardingTarget returns nil and the call crashes with "unrecognized selector".

        let swizzler = try? UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()
        defer { swizzler?.unswizzle() }

        // Given - a scroll view with a delegate; scrolling works normally
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 1_000)
        var originalDelegate: MockScrollViewDelegate? = MockScrollViewDelegate()
        scrollView.delegate = originalDelegate
        scrollView.setContentOffset(CGPoint(x: 0, y: 50), animated: false)

        // When - the delegate is deallocated
        originalDelegate = nil

        // Then - scrolling must not crash; the proxy must have been released with the delegate
        scrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
    }

    // MARK: - Circular Proxy Chain (regression for RxSwift-style delegate proxy conflict)

    func testRespondsTo_withCircularProxyChain_doesNotCauseInfiniteRecursion() {
        // Regression test: when Datadog's proxy and a third-party proxy (e.g. RxSwift's
        // DelegateProxy) mutually reference each other, `responds(to:)` must not infinitely recurse.
        //
        // Circular chain:
        //   ddProxy.originalDelegate  = thirdPartyProxy
        //   thirdPartyProxy.forwardTo = ddProxy

        // Given
        let thirdPartyProxy = ThirdPartyDelegateProxy()
        let ddProxy = UIScrollViewDelegateProxy(originalDelegate: thirdPartyProxy, handler: handler)
        thirdPartyProxy.forwardToDelegate = ddProxy

        // When / Then - must return without stack-overflowing
        let selector = #selector(UIScrollViewDelegate.scrollViewDidScroll(_:))
        XCTAssertFalse(ddProxy.responds(to: selector))
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
