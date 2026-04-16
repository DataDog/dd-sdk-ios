/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS) || os(visionOS)

import XCTest
import TestUtilities
@testable import DatadogRUM

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

        // Then - getter returns the original delegate (proxy is internal implementation detail)
        XCTAssertTrue(scrollView.delegate === delegate)
    }

    // MARK: - Delegate getter transparency

    func testSwizzle_whenReadingDelegate_returnsOriginalDelegateNotProxy() throws {
        // Regression test for: https://github.com/DataDog/dd-sdk-ios/issues/2760
        // When customers set their own delegate and our is swizzler active, the
        // getter should not return Datadog's internal UIScrollViewDelegateProxy.

        // Given
        guard let handler else {
            XCTFail("Handler should be initialized")
            return
        }
        swizzler = try UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()

        let scrollView = UIScrollView()
        let originalDelegate = MockScrollViewDelegate()

        // When
        scrollView.delegate = originalDelegate

        // Then - getter must return the original delegate, not Datadog's proxy
        XCTAssertTrue(scrollView.delegate === originalDelegate)
        XCTAssertFalse(scrollView.delegate is UIScrollViewDelegateProxy)
    }

    // MARK: - Third-party proxy conflict (regression for RxSwift-style delegate proxy crash)

    func testSwizzle_whenThirdPartyProxyCapturesDatadogProxy_doesNotCreateCircularRespondsToRecursion() throws {
        // Regression test for stack overflow crash when Datadog's UIScrollViewSwizzler is active
        // alongside a third-party delegate proxy (e.g. RxSwift's DelegateProxy).
        //
        // Without the getter swizzle, a third-party proxy reading `scrollView.delegate` would get
        // `ddProxy` back and store it as its forward target, creating a circular chain:
        //   ddProxy.originalDelegate = thirdPartyProxy, thirdPartyProxy.forwardToDelegate = ddProxy
        // Any call to `responds(to:)` on `ddProxy` would then infinitely recurse → stack overflow.
        //
        // With the getter swizzle, the getter transparently returns the app's delegate (not `ddProxy`),
        // so the third-party proxy stores the real delegate and the chain stays linear:
        //   ddProxy → thirdPartyProxy → originalDelegate (no cycle)

        // Given
        guard let handler else {
            XCTFail("Handler should be initialized")
            return
        }
        swizzler = try UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()

        let scrollView = UIScrollView()
        let originalDelegate = MockScrollViewDelegate()

        // App sets delegate — swizzler wraps it in ddProxy; getter transparently returns the app's delegate
        scrollView.delegate = originalDelegate
        XCTAssertTrue(scrollView.delegate === originalDelegate)

        // Third-party proxy reads the delegate (gets app's delegate, not ddProxy) and sets itself
        // as the new delegate — this is how RxSwift sets up rx.contentOffset
        let thirdPartyProxy = ThirdPartyDelegateProxy()
        thirdPartyProxy.forwardToDelegate = scrollView.delegate as? (NSObject & UIScrollViewDelegate)
        scrollView.delegate = thirdPartyProxy  // triggers swizzler → ddProxy.originalDelegate = thirdPartyProxy

        // When / Then — must not stack-overflow
        let selector = #selector(UIScrollViewDelegate.scrollViewDidScroll(_:))
        XCTAssertFalse(scrollView.delegate?.responds(to: selector) ?? false)
    }

    // MARK: - Setter re-entrancy guard (regression for RxSwift-style setter re-entry crash)

    func testSetterReentrancyGuard_whenThirdPartySwizzleReCallsSetterViaDispatch_doesNotCauseStackOverflow() throws {
        // Regression test for infinite recursion when a third-party library swizzles
        // UIScrollView.delegate setter (installed before Datadog) and, from within
        // Datadog's `previousImplementation` call, re-calls `scrollView.delegate = itsProxy`
        // via full ObjC dispatch — re-entering Datadog's swizzle before it has returned.
        //
        // Swizzle chain (Datadog last = first to fire):
        //   [Datadog.SetDelegate] → [ThirdParty swizzle] → [original UIScrollView setter]
        //
        // Without the scrollViewsBeingSet guard (would crash with stack overflow):
        //   1. App sets delegate → Datadog fires → creates DDProxy → calls previousImpl (ThirdParty)
        //   2. ThirdParty wraps DDProxy in txProxy → dispatch: scrollView.delegate = txProxy
        //   3. Datadog fires again → creates DDProxy2 → calls previousImpl (ThirdParty) → … ∞
        //
        // With the guard (correct):
        //   1. App sets delegate → Datadog fires → inserts scrollView in set → creates DDProxy → calls previousImpl
        //   2. ThirdParty wraps DDProxy → dispatch: scrollView.delegate = txProxy
        //   3. Datadog fires → scrollView IS in set → guard fires → passes txProxy through directly
        //   4. Chain resolves; defer removes scrollView from set

        guard let handler else {
            XCTFail("Handler should be initialized")
            return
        }

        // Capture the current setter IMP before any test swizzle is installed
        let setterSel = #selector(setter: UIScrollView.delegate)
        guard let setterMethod = class_getInstanceMethod(UIScrollView.self, setterSel) else {
            XCTFail("UIScrollView.delegate setter method not found in ObjC runtime")
            return
        }
        let savedIMP = method_getImplementation(setterMethod)

        // Build and install a raw ObjC-style "third-party" setter swizzle.
        // This simulates the pattern used by RxSwift's DelegateProxy:
        // - If the incoming delegate is NOT already a ThirdPartyDelegateProxy:
        //   wrap it in one and re-call the setter via ObjC dispatch (the dangerous re-entry).
        // - If it already IS a ThirdPartyDelegateProxy: pass through to the previous IMP.
        typealias SetterCIMP = @convention(c) (UIScrollView, Selector, UIScrollViewDelegate?) -> Void

        // Holds the IMP that was current before the third-party swizzle was installed,
        // so the pass-through branch can call it correctly.
        class IMPHolder { var imp: IMP? }
        let prevHolder = IMPHolder()

        // Holds a strong reference to the ThirdPartyDelegateProxy created in the block.
        // UIScrollView.delegate is a weak property, so without this the proxy would be
        // deallocated immediately after the block exits — just as in real frameworks the
        // DelegateProxy is retained by the observable chain.
        class ProxyHolder { var proxy: ThirdPartyDelegateProxy? }
        let proxyHolder = ProxyHolder()

        let thirdPartyBlock: @convention(block) (UIScrollView, UIScrollViewDelegate?) -> Void = { scrollView, delegate in
            guard let delegate = delegate, !(delegate is ThirdPartyDelegateProxy) else {
                // Pass through to whatever IMP was current before the third-party installed
                if let prev = prevHolder.imp {
                    unsafeBitCast(prev, to: SetterCIMP.self)(scrollView, setterSel, delegate)
                }
                return
            }
            // Simulate RxSwift DelegateProxy: wrap the delegate and re-call via ObjC dispatch.
            // This call goes through the full swizzle chain from the top (re-enters Datadog's swizzle).
            let thirdPartyProxy = ThirdPartyDelegateProxy()
            thirdPartyProxy.forwardToDelegate = delegate as? (NSObject & UIScrollViewDelegate)
            proxyHolder.proxy = thirdPartyProxy  // Retain so the weak scrollView.delegate stays alive
            scrollView.delegate = thirdPartyProxy
        }
        let thirdPartyIMP = imp_implementationWithBlock(thirdPartyBlock)
        // Install the third-party swizzle; record the IMP it replaces for pass-through
        prevHolder.imp = method_setImplementation(setterMethod, thirdPartyIMP)

        // Now install Datadog's swizzle (it captures thirdPartyIMP as its previousImplementation)
        swizzler = try UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()

        defer {
            // Cleanup in reverse installation order:
            // 1. Remove Datadog's swizzle (restores method IMP to thirdPartyIMP)
            swizzler?.unswizzle()
            swizzler = nil  // Prevent double-unswizzle in tearDown
            // 2. Restore the IMP that was in place before the third-party test swizzle
            method_setImplementation(setterMethod, savedIMP)
        }

        let scrollView = UIScrollView()
        let originalDelegate = MockScrollViewDelegate()

        // When — must not cause infinite recursion / stack overflow
        scrollView.delegate = originalDelegate

        // Then — the delegate chain was established without crashing
        XCTAssertNotNil(scrollView.delegate)
    }

    func testSetterReentrancyGuard_isReleasedAfterEachCall_soSubsequentIndependentCallsWork() throws {
        // Verify that the scrollViewsBeingSet guard is cleared (via defer) after each
        // completed setter call, so that a second, independent call to the same scroll
        // view's delegate setter is not mistakenly treated as re-entrant.
        //
        // If the guard were not cleared (e.g. defer missing), the second call would hit
        // the guard and bypass proxy creation, breaking scroll-event tracking for that view.

        guard let handler else {
            XCTFail("Handler should be initialized")
            return
        }
        swizzler = try UIScrollViewSwizzler(handler: handler)
        swizzler?.swizzle()

        let scrollView = UIScrollView()
        let delegate1 = MockScrollViewDelegate()
        let delegate2 = MockScrollViewDelegate()

        // When — two independent (non-re-entrant) setter calls in sequence
        scrollView.delegate = delegate1
        scrollView.delegate = delegate2

        // Then — the second assignment takes effect; getter returns delegate2 (not delegate1)
        XCTAssertTrue(scrollView.delegate === delegate2)
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
        scrollView.delegate = delegate

        // Then - getter consistently returns the original delegate
        XCTAssertTrue(scrollView.delegate === delegate)
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
}

#endif
