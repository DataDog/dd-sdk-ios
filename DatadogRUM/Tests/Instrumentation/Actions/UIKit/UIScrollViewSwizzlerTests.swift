/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

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
