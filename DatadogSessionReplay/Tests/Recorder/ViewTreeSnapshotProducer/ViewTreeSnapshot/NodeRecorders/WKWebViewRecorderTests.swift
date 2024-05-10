/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import WebKit
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

class WKWebViewRecorderTests: XCTestCase {
    private let recorder = WKWebViewRecorder()
    /// The web-view under test.
    private let webView = WKWebView()
    /// `ViewAttributes` simulating common attributes of web-view's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenViewIsNotOfExpectedType() {
        // Given
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: .mockAny(), in: .mockAny()))
    }

    func testWhenWebViewIsNotVisible() throws {
        // Given
        let viewAttributes: ViewAttributes = .mock(fixture: .invisible)

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: webView, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "WebView's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? WKWebViewWireframesBuilder)
        let wireframes = builder.buildWireframes(with: WireframesBuilder())
        XCTAssert(wireframes.isEmpty)
    }

    func testWhenWebViewIsVisible() throws {
        // Given
        let viewAttributes: ViewAttributes = .mock(fixture: .visible())

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: webView, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        // Then
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "WebView's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? WKWebViewWireframesBuilder)
        let wireframes = builder.buildWireframes(with: WireframesBuilder())
        XCTAssertFalse(wireframes.isEmpty)
    }

    func testVisibleWebViewSlot() throws {
        // Given
        let attributes: ViewAttributes = .mock(fixture: .visible())
        let slotID = webView.hash

        let builder = WireframesBuilder(webViewSlotIDs: [slotID])

        // When
        let wireframes = WKWebViewWireframesBuilder(slotID: webView.hash, attributes: attributes)
            .buildWireframes(with: builder)

        // Then
        XCTAssertEqual(wireframes.count, 1)

        guard case let .webviewWireframe(wireframe) = wireframes.first else {
            return XCTFail("First wireframe needs to be webviewWireframe case")
        }

        XCTAssertEqual(wireframe.id, Int64(webView.hash))
        XCTAssertEqual(wireframe.slotId, String(webView.hash))
        XCTAssertNil(wireframe.clip)
        XCTAssertEqual(wireframe.x, Int64(withNoOverflow: attributes.frame.minX))
        XCTAssertEqual(wireframe.y, Int64(withNoOverflow: attributes.frame.minY))
        XCTAssertEqual(wireframe.width, Int64(withNoOverflow: attributes.frame.width))
        XCTAssertEqual(wireframe.height, Int64(withNoOverflow: attributes.frame.height))
        XCTAssertTrue(wireframe.isVisible ?? false)
        XCTAssertTrue(builder.hiddenWebViewWireframes().isEmpty, "webview slot should be removed from builder")
    }
}

#endif
