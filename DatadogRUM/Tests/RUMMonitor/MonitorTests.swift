/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class MonitorTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testWhenSessionIsSampled_itSetsRUMContextInCore() throws {
        // Given
        let sampler = Sampler(samplingRate: 100)

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, sessionSampler: sampler),
            dateProvider: DateProviderMock()
        )
        monitor.startView(key: "foo")

        // Then
        let expectedContext = monitor.currentRUMContext
        let rumContext = try XCTUnwrap(featureScope.contextMock.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertEqual(rumContext.applicationID, expectedContext.rumApplicationID)
        XCTAssertEqual(rumContext.sessionID, expectedContext.sessionID.toRUMDataFormat)
        XCTAssertEqual(rumContext.viewID, expectedContext.activeViewID?.toRUMDataFormat)
    }

    func testWhenSessionIsNotSampled_itSetsNoRUMContextInCore() throws {
        // Given
        let sampler = Sampler(samplingRate: 0)

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, sessionSampler: sampler),
            dateProvider: DateProviderMock()
        )
        monitor.startView(key: "foo")

        // Then
        XCTAssertNil(featureScope.contextMock.additionalContext(ofType: RUMCoreContext.self))
    }

    func testStartView_withViewController_itUsesClassNameAsViewName() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, sessionSampler: .mockKeepAll()),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc)

        // Then
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewName, "SomeViewController")
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }

    func testStartView_withViewController_itUsesClassNameAsViewPath() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, sessionSampler: .mockKeepAll()),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc, name: "Some View")

        // Then
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewName, "Some View")
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }
}

// MARK: - Convenience

private extension Monitor {
    /// Returns RUM context assuming that some view is started.
    var currentRUMContext: RUMContext { scopes.activeSession!.viewScopes.last!.context }
}
