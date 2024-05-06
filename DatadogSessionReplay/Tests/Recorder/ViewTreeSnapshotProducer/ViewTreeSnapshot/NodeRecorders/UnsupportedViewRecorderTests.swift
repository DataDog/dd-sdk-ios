/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import WebKit
import SwiftUI
import SafariServices
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
class UnsupportedViewRecorderTests: XCTestCase {
    private let recorder = UnsupportedViewRecorder()

    private let unsupportedViews: [UIView] = [
        UIProgressView(), UIActivityIndicatorView()
    ].compactMap { $0 }
    private let expectedUnsupportedViewsClassNames = [
        "UIProgressView", "UIActivityIndicatorView", "WKWebView"
    ]
    private let otherViews = [UILabel(), UIView(), UIImageView(), UIScrollView(), WKWebView()]

    /// `ViewAttributes` simulating common attributes of the view.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        try unsupportedViews.forEach { view in
            let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
            XCTAssertTrue(semantics is InvisibleElement)
        }
        otherViews.forEach { view in
            XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        }
    }

    func testWhenViewIsVisible() throws {
        // When
        viewAttributes = .mock(fixture: .visible([.noAppearance, .someAppearance].randomElement()!))

        // Then
        try unsupportedViews.enumerated().forEach { index, view in
            let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
            XCTAssertTrue(semantics is SpecificElement)
            XCTAssertEqual(semantics.subtreeStrategy, .ignore)
            let wireframeBuilder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UnsupportedViewWireframesBuilder)
            XCTAssertEqual(wireframeBuilder.unsupportedClassName, expectedUnsupportedViewsClassNames[index])
        }
        otherViews.forEach { view in
            XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        }
    }

    func testWhenViewIsUnsupportedViewControllersRootView() throws {
        var context = ViewTreeRecordingContext.mockRandom()
        context.viewControllerContext.isRootView = true
        context.viewControllerContext.parentType = [.safari, .activity, .swiftUI].randomElement()

        let semantics = try XCTUnwrap(recorder.semantics(of: UIView(), with: .mock(fixture: .visible(.someAppearance)), in: context))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
        let wireframeBuilder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UnsupportedViewWireframesBuilder)
        XCTAssertNotNil(wireframeBuilder.unsupportedClassName)
    }
}
