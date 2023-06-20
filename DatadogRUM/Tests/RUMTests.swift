/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class RUMTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: RUMConfiguration = .mockAny()

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
    }

    override func tearDown() {
        core = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
    }

    func testWhenNotEnabled_thenRUMMonitorIsNotAvailable() {
        // When
        XCTAssertNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is NOPMonitor)
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // When
        RUM.enable(with: .mockAny(), in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `RUM.enable(with:)`."
        )
    }

    func testWhenEnabled_thenRUMMonitorIsAvailable() {
        // When
        RUM.enable(with: config, in: core)
        XCTAssertNotNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
    }

    // MARK: - Configuration Tests

    func testWhenEnabledWithAllInstrumentations() throws {
        // Given
        config.instrumentation = .init(
            uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
            uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicateMock(),
            longTaskThreshold: 0.5
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(monitor, rum.instrumentation.viewsHandler.subscriber)
        XCTAssertIdentical(monitor, (rum.instrumentation.actionsHandler as? UIKitRUMUserActionsHandler)?.subscriber)
        XCTAssertIdentical(monitor, rum.instrumentation.longTasks?.subscriber)
    }

    func testWhenEnabledWithNoInstrumentations() throws {
        // Given
        config.instrumentation = .init(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMUserActionsPredicate: nil,
            longTaskThreshold: nil
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(
            monitor,
            rum.instrumentation.viewsHandler.subscriber,
            "It must always subscribe RUM monitor to `RUMViewsHandler` as it is required for manual SwiftUI instrumentation"
        )
        XCTAssertNil(rum.instrumentation.actionsHandler)
        XCTAssertNil(rum.instrumentation.longTasks)
    }

    func testWhenEnabledWithFirstPartyHosts() throws {
        // Given
        oneOf([
            { self.config.firstPartyHosts = .init([:]) }, // even if empty - first party hosts can be added later in `DDURLSessionDelegate`
            { self.config.firstPartyHosts = .init(["foo.com": [.datadog]]) }
        ])

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should enable `NetworkInstrumentationFeature`"
        )
        let rumResourcesHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: URLSessionRUMResourcesHandler.self),
            "It should register `URLSessionRUMResourcesHandler` to `NetworkInstrumentationFeature`"
        )
        XCTAssertIdentical(
            monitor,
            rumResourcesHandler.subscriber,
            "It must subscribe `RUMMonitor` to `URLSessionRUMResourcesHandler`"
        )
    }

    func testWhenEnabledWithNoFirstPartyHosts() {
        // Given
        config.firstPartyHosts = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
        XCTAssertNil(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should not enable `NetworkInstrumentationFeature`"
        )
    }

    func testWhenEnabledWithCustomIntakeURL() throws {
        // Given
        let randomURL: URL = .mockRandom()
        config.customIntakeURL = randomURL

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertEqual((rum.requestBuilder as? RequestBuilder)?.customIntakeURL, randomURL)
    }

    func testWhenEnabledWithNoCustomIntakeURL() throws {
        // Given
        config.customIntakeURL = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNil((rum.requestBuilder as? RequestBuilder)?.customIntakeURL)
    }

    func testWhenEnabledWithDebugArgument() {
        // Given
        config.processInfo = ProcessInfoMock(arguments: [RUMFeature.LaunchArguments.DebugRUM])

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core).debug)
    }

    func testWhenEnabledWithNoDebugArgument() {
        // Given
        config.processInfo = ProcessInfoMock(arguments: [])

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertFalse(RUMMonitor.shared(in: core).debug)
    }

    // MARK: - Behaviour Tests

    func testWhenEnabled_itSetsRUMContextInCore() {
        let core = PassthroughCoreMock()
        let applicationID: String = .mockRandom()
        let sessionID: RUMUUID = .mockRandom()

        // When
        RUM.enable(
            with: .mockWith(
                applicationID: applicationID,
                uuidGenerator: RUMUUIDGeneratorMock(uuid: sessionID),
                sessionSampler: .mockKeepAll()
            ),
            in: core
        )

        // Then
        DDAssertReflectionEqual(
            core.context.featuresAttributes["rum"],
            FeatureBaggage(
                [
                    "ids": [
                        "application_id": applicationID,
                        "session_id": sessionID.toRUMDataFormat,
                        "view.id": nil,
                        "user_action.id": nil
                    ]
                ]
            )
        )
    }
}
