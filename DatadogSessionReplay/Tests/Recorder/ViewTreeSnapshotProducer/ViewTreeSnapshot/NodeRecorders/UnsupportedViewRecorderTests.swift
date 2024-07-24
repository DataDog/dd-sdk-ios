/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import WebKit
import SwiftUI
import SafariServices
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
class UnsupportedViewRecorderTests: XCTestCase {
    private let recorder = UnsupportedViewRecorder(identifier: UUID())

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

#endif
