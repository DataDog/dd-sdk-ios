/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogWebViewTracking

class WebViewFeatureTests: XCTestCase {
    func testHandlerRegistration() throws {
        let core = SingleFeatureCoreMock<WebViewFeature>()

        let identifiers = (0..<10).map { NSNumber(value: $0) }
        try identifiers.forEach {
            try core.register(scriptMessageHandler: DDScriptMessageHandler(emitter: .mockAny()), forIdentifier: .init($0))
        }

        let feature = core.get(feature: WebViewFeature.self)
        XCTAssertEqual(feature?.handlers.count, 10)

        identifiers.forEach {
            core.unregisterScriptMessageHandler(forIdentifier: .init($0))
        }

        XCTAssertEqual(feature?.handlers.count, 0)
    }

    // MARK: - Thread Safety

    func testRandomlyRegisteringConcurrentlyDoesNotCrash() {
        let feature = WebViewFeature()
        let handlers = (0..<10).map { _ in (key: NSObject(), value: DDScriptMessageHandler(emitter: .mockAny())) }

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                {
                    let handler = handlers.randomElement()!
                    feature.handlers[.init(handler.key)] = handler.value
                },
                {
                    let handler = handlers.randomElement()!
                    feature.handlers[.init(handler.key)] = nil
                },
                { _ = feature.handlers.count }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }
}
