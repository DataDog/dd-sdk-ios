/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Testing
import CoreGraphics
@testable import DatadogSessionReplay

@MainActor
struct WKWebViewSessionReplayTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func returnsOriginalFrameWhenContentInsetAdjustmentBehaviorIsNever() {
        // Given
        let webView = TestWKWebView(topSafeAreaInset: 44, contentInsetAdjustmentBehavior: .never)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)

        // When
        let result = webView.contentInsetAdjustedFrame(for: frame)

        // Then
        #expect(result == frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func returnsOriginalFrameWhenFrameStartsBelowSafeArea() {
        // Given
        let webView = TestWKWebView(topSafeAreaInset: 44, contentInsetAdjustmentBehavior: .always)
        let frame = CGRect(x: 0, y: 60, width: 100, height: 50)

        // When
        let result = webView.contentInsetAdjustedFrame(for: frame)

        // Then
        #expect(result == frame)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test
    func offsetsFrameByTopSafeAreaWhenFrameStartsAboveSafeArea() {
        // Given
        let webView = TestWKWebView(topSafeAreaInset: 44, contentInsetAdjustmentBehavior: .always)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)

        // When
        let result = webView.contentInsetAdjustedFrame(for: frame)

        // Then
        #expect(result == frame.offsetBy(dx: 0, dy: 44))
    }
}
#endif
