/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class MonitorTests: XCTestCase {
    private let scope = FeatureScopeMock()

    func testWhenSessionIsSampled_itSetsRUMContextInCore() throws {
        // Given
        let sampler = Sampler(samplingRate: 100)

        // When
        let monitor = Monitor(
            featureScope: scope,
            dependencies: .mockWith(scope: scope, sessionSampler: sampler),
            dateProvider: DateProviderMock()
        )
        monitor.startView(key: "foo")
        monitor.flush()

        // Then
        let expectedContext = monitor.currentRUMContext
        let rumBaggage = try XCTUnwrap(scope.contextMock.baggages[RUMFeature.name])
        let rumContext = try rumBaggage.decode(type: RUMCoreContext.self)
        XCTAssertEqual(rumContext.applicationID, expectedContext.rumApplicationID)
        XCTAssertEqual(rumContext.sessionID, expectedContext.sessionID.toRUMDataFormat)
        XCTAssertEqual(rumContext.viewID, expectedContext.activeViewID?.toRUMDataFormat)
    }

    func testWhenSessionIsNotSampled_itSetsNoRUMContextInCore() throws {
        // Given
        let sampler = Sampler(samplingRate: 0)

        // When
        let monitor = Monitor(
            featureScope: scope,
            dependencies: .mockWith(scope: scope, sessionSampler: sampler),
            dateProvider: DateProviderMock()
        )
        monitor.startView(key: "foo")
        monitor.flush()

        // Then
        XCTAssertNil(scope.contextMock.baggages[RUMFeature.name])
    }

    func testStartView_withViewController_itUsesClassNameAsViewName() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            featureScope: scope,
            dependencies: .mockWith(scope: scope, sessionSampler: .mockKeepAll()),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc)
        monitor.flush()

        // Then
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewName, "SomeViewController")
        XCTAssertEqual(monitor.scopes.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }

    func testStartView_withViewController_itUsesClassNameAsViewPath() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            featureScope: scope,
            dependencies: .mockWith(scope: scope, sessionSampler: .mockKeepAll()),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc, name: "Some View")
        monitor.flush()

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
