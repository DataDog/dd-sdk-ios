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

    // MARK: - RUM-16361: Forwarding crash regression

    /// Reproduces the crash from RUMS-5962 / RUMS-5941 and GH #2867.
    ///
    /// Crash signature: `-[DatadogRUM.UIScrollViewDelegateProxy <selector>]: unrecognized
    /// selector`, dispatched from `_notifyDidScroll` during view-controller teardown.
    ///
    /// Mechanism: a VC that owns its scroll view AND is its delegate hits a dealloc-time
    /// race — the VC's `deallocating` flag zeros the weak `originalDelegate` while the
    /// proxy is still alive. UIKit dispatches a cached selector to the proxy; the proxy
    /// doesn't implement it directly; `forwardingTarget(for:)` returns nil; the runtime
    /// raises "unrecognized selector".
    func test_whenOriginalDelegateIsDeallocated_dispatchingForwardedSelector_doesNotCrash() {
        // Given - a proxy whose original delegate has been deallocated.
        var delegate: MockScrollViewDelegate? = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)
        delegate = nil

        XCTAssertNil(proxy.originalDelegate, "weak reference must be nil after delegate deallocates")

        // When - `perform(_:with:)` exercises the same ObjC forwarding chain UIKit uses
        // internally (objc_msgSend → forwardingTarget(for:) → forwardInvocation:).
        let scrollView = UIScrollView()
        _ = proxy.perform(
            #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)),
            with: scrollView
        )

        // Then - the proxy handles the dispatch without crashing.
    }

    /// Same mechanism as above, but with a UITableViewDelegate selector — proves the fix
    /// covers selectors outside `UIScrollViewDelegate`. Mirrors the RxCocoa-wrapped
    /// `tableView:estimatedHeightForHeaderInSection:` crash from RUMS-5941.
    func test_whenOriginalDelegateIsDeallocated_dispatchingUITableViewDelegateSelector_doesNotCrash() {
        // Given - a proxy whose original delegate (a UITableViewDelegate) has been deallocated.
        var delegate: MockTableViewDelegate? = MockTableViewDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)
        delegate = nil

        XCTAssertNil(proxy.originalDelegate, "weak reference must be nil after delegate deallocates")

        // When - dispatch a UITableViewDelegate selector with a correctly typed function
        // pointer (scalar `Int` argument, `CGFloat` return).
        let selector = #selector(UITableViewDelegate.tableView(_:estimatedHeightForHeaderInSection:))
        typealias EstimatedHeightIMP = @convention(c) (AnyObject, Selector, UITableView, Int) -> CGFloat
        let implementation = unsafeBitCast(proxy.method(for: selector), to: EstimatedHeightIMP.self)
        let result = implementation(proxy, selector, UITableView(), 0)

        // Then - the proxy handles the dispatch without crashing, returning the zeroed default.
        XCTAssertEqual(result, 0)
    }

    /// Verifies that non-void forwarded selectors get a zero/nil default return (instead
    /// of undefined bytes) when the original delegate is gone. Uses an object-returning
    /// UIScrollViewDelegate selector since `perform(_:with:)` can only validate object
    /// returns; the underlying `setReturnValue:` fix in the base class zeros the entire
    /// `methodReturnLength`, so verifying one return type implicitly covers all of them.
    func test_whenOriginalDelegateIsDeallocated_dispatchingNonVoidForwardedSelector_returnsZeroedDefault() {
        // Given - a proxy whose original delegate has been deallocated.
        var delegate: MockScrollViewDelegate? = MockScrollViewDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)
        delegate = nil

        XCTAssertNil(proxy.originalDelegate)

        // When - dispatching `viewForZooming(in:)` (returns UIView?) through the forwarding chain.
        let result = proxy.perform(
            #selector(UIScrollViewDelegate.viewForZooming(in:)),
            with: UIScrollView()
        )

        // Then - the proxy must return nil (zeroed object pointer), not garbage.
        XCTAssertNil(result, "Expected nil for object-typed forwarded selector when delegate is gone")
    }

    // MARK: - RUM-16361: Forwarding happy path (via __dd_private_DDForwardingProxyBase)

    /// Proves alive-delegate forwarding still works end-to-end for a UIScrollViewDelegate
    /// selector the proxy does NOT implement directly.
    func test_whenOriginalDelegateIsAlive_dispatchingForwardedSelector_reachesTheOriginalDelegate() {
        // Given - a proxy whose original delegate is alive and counts calls.
        let delegate = CountingDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)

        // When - dispatch a forwarded UIScrollViewDelegate selector.
        _ = proxy.perform(
            #selector(UIScrollViewDelegate.scrollViewDidScroll(_:)),
            with: UIScrollView()
        )

        // Then - the call reached the original delegate.
        XCTAssertEqual(delegate.scrollViewDidScrollCount, 1)
    }

    /// Same as above for a UITableViewDelegate selector — exercises the protocol-lookup
    /// branch in the base class's `methodSignatureForSelector:`.
    func test_whenOriginalDelegateIsAlive_dispatchingUITableViewDelegateSelector_reachesTheOriginalDelegate() {
        // Given - a proxy whose UITableViewDelegate target is alive and counts calls.
        let delegate = CountingDelegate()
        let proxy = UIScrollViewDelegateProxy(originalDelegate: delegate, handler: handler)

        // When - dispatch a UITableViewDelegate selector with a correctly typed function
        // pointer (scalar `Int` argument, `CGFloat` return).
        let selector = #selector(UITableViewDelegate.tableView(_:estimatedHeightForHeaderInSection:))
        typealias EstimatedHeightIMP = @convention(c) (AnyObject, Selector, UITableView, Int) -> CGFloat
        let implementation = unsafeBitCast(proxy.method(for: selector), to: EstimatedHeightIMP.self)
        let result = implementation(proxy, selector, UITableView(), 0)

        // Then - the call reached the original delegate and returned its value.
        XCTAssertEqual(delegate.estimatedHeightCallCount, 1)
        XCTAssertEqual(result, 44)
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

private class MockTableViewDelegate: NSObject, UITableViewDelegate {
    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        44
    }
}

/// Counts forwarded calls. Conforms to UITableViewDelegate (which extends UIScrollViewDelegate),
/// so satisfies both forwarding paths exercised by the happy-path tests.
private class CountingDelegate: NSObject, UITableViewDelegate {
    var scrollViewDidScrollCount = 0
    var estimatedHeightCallCount = 0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollViewDidScrollCount += 1
    }

    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        estimatedHeightCallCount += 1
        return 44
    }
}

#endif
