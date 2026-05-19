/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) || os(visionOS)

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

    // MARK: - Regression for RUM-16361: Forwarding after originalDelegate deallocates

    /// Reproduces the crash reported in:
    /// - RUM-16361 / RUMS-5941 (Salesforce escalation; Kidsnote SDK 3.9.1, SOOP SDK 3.11.0)
    /// - https://github.com/DataDog/dd-sdk-ios/issues/2867 (Shaadi, SDK 3.10.0)
    ///
    /// Crash signature:
    ///   NSInvalidArgumentException
    ///   -[DatadogRUM.UIScrollViewDelegateProxy scrollViewDidScroll:]: unrecognized selector
    ///   ___forwarding___ → _CF_forwarding_prep_0 → _notifyDidScroll
    ///
    /// Mechanism (production):
    /// A UIViewController owns its UIScrollView AND is its delegate. When the VC deallocates,
    /// its `deallocating` flag is set BEFORE its associated objects are released. Inside that
    /// window, UIKit may dispatch `scrollViewDidScroll:` to the still-alive proxy (e.g. from
    /// layout invalidation during the scroll view's own teardown). The proxy does not implement
    /// that selector directly, so the ObjC runtime invokes `forwardingTarget(for:)` — which
    /// reads the weak `originalDelegate` (now nil because the VC is mid-dealloc) and returns
    /// nil. The runtime then raises "unrecognized selector".
    ///
    /// Why prior fixes missed it:
    /// - PR #2776 tied proxy lifetime to delegate lifetime, but the proxy is still alive during
    ///   the VC's dealloc body. The bug is about reading `originalDelegate` after the delegate's
    ///   `deallocating` flag is set, not about the proxy outliving the delegate by minutes.
    /// - PR #2791 added a setter re-entrancy guard; orthogonal code path.
    func test_whenOriginalDelegateIsDeallocated_dispatchingForwardedSelector_doesNotCrash() {
        // Given - a proxy whose original delegate has been deallocated. The weak
        // `originalDelegate` reference must be nil; the proxy itself is still alive.
        var delegate: MockScrollViewDelegate? = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)
        delegate = nil

        XCTAssertNil(proxy.originalDelegate, "Sanity: weak reference must be nil after delegate deallocates")

        // When - UIKit dispatches a forwarded UIScrollViewDelegate selector to the proxy.
        // `perform(_:with:)` exercises the same ObjC forwarding chain UIKit uses internally
        // (objc_msgSend → forwardingTarget(for:) → forwardInvocation:).
        let scrollView = UIScrollView()
        _ = proxy.perform(
            #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)),
            with: scrollView
        )

        // Then - the proxy must handle the dispatch without crashing. The unfixed proxy raises
        // NSInvalidArgumentException from inside `perform`, which XCTest reports as a failure.
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
