/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest

@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 13.0, *)
class UIHostingViewRecorderTests: XCTestCase {
    let recorder = UIHostingViewRecorder()
    /// `ViewAttributes` simulating common attributes of the view.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testRandomTree() throws {
        // Given
        let host = UIHostingViewMock(renderer: .mockRandom())
        let semantics = recorder.semantics(of: host, with: viewAttributes, in: .mockAny())
        let element = try XCTUnwrap(semantics as? SpecificElement)
        XCTAssertEqual(element.subtreeStrategy, .record)
        let node = try XCTUnwrap(element.nodes.first)
        XCTAssertEqual(node.viewAttributes, viewAttributes)

        let builder = WireframesBuilder()
        let wireframeBuilder = try XCTUnwrap(node.wireframesBuilder as? UIHostingUIWireframesBuilder)
        let wireframes = wireframeBuilder.buildWireframes(with: builder)
        XCTAssertFalse(wireframes.isEmpty)
    }
}

#endif
