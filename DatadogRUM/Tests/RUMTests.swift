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
    private var config: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        config = RUM.Configuration(applicationID: .mockAny())
    }

    override func tearDown() {
        core = nil
        config = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
        XCTAssertEqual(PassthroughCoreMock.referenceCount, 0)
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
        RUM.enable(with: config, in: NOPDatadogCore())

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

    func testWhenEnabledWithDefaultConfiguration() throws {
        // Given
        let applicationID: String = .mockRandom()
        config = RUM.Configuration(applicationID: applicationID)

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        let crashReportReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(monitor.scopes.dependencies.rumApplicationID, applicationID)
        XCTAssertEqual(monitor.scopes.dependencies.sessionSampler.samplingRate, 100)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 20)
        XCTAssertEqual(telemetryReceiver?.metricsExtraSampler.samplingRate, 15)
        XCTAssertEqual(crashReportReceiver?.sessionSampler.samplingRate, 100)
    }

    func testWhenEnabledWithAllInstrumentations() throws {
        // Given
        config.uiKitViewsPredicate = UIKitRUMViewsPredicateMock()
        config.uiKitActionsPredicate = UIKitRUMActionsPredicateMock()
        config.longTaskThreshold = 0.5

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
        config.uiKitViewsPredicate = nil
        config.uiKitActionsPredicate = nil
        config.longTaskThreshold = nil

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

    func testWhenEnabledWithURLSessionTracking() throws {
        // Given
        config.urlSessionTracking = .init()

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

    func testWhenEnabledWithNoURLSessionTracking() {
        // Given
        config.urlSessionTracking = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
        XCTAssertNil(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should not enable `NetworkInstrumentationFeature`"
        )
    }

    func testWhenEnabledWithVitalsUpdateFrequency() throws {
        // Given
        config.vitalsUpdateFrequency = [.frequent, .average, .rare].randomElement()!

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNotNil(monitor.scopes.dependencies.vitalsReaders)
    }

    func testWhenEnabledWithNoVitalsUpdateFrequency() throws {
        // Given
        config.vitalsUpdateFrequency = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNil(monitor.scopes.dependencies.vitalsReaders)
    }

    func testWhenEnabledWithEventMappers() throws {
        // Given
        config.viewEventMapper = { $0 }
        config.resourceEventMapper = { $0 }
        config.actionEventMapper = { $0 }
        config.errorEventMapper = { $0 }
        config.longTaskEventMapper = { $0 }

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let eventsMapper = monitor.scopes.dependencies.eventBuilder.eventsMapper
        XCTAssertNotNil(eventsMapper.viewEventMapper)
        XCTAssertNotNil(eventsMapper.resourceEventMapper)
        XCTAssertNotNil(eventsMapper.actionEventMapper)
        XCTAssertNotNil(eventsMapper.errorEventMapper)
        XCTAssertNotNil(eventsMapper.longTaskEventMapper)
    }

    func testWhenEnabledWithNoEventMappers() throws {
        // Given
        config.viewEventMapper = nil
        config.resourceEventMapper = nil
        config.actionEventMapper = nil
        config.errorEventMapper = nil
        config.longTaskEventMapper = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let eventsMapper = monitor.scopes.dependencies.eventBuilder.eventsMapper
        XCTAssertNil(eventsMapper.viewEventMapper)
        XCTAssertNil(eventsMapper.resourceEventMapper)
        XCTAssertNil(eventsMapper.actionEventMapper)
        XCTAssertNil(eventsMapper.errorEventMapper)
        XCTAssertNil(eventsMapper.longTaskEventMapper)
    }

    func testWhenEnabledWithSessionStartListener() throws {
        // Given
        config.onSessionStart = { _, _ in }

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNotNil(monitor.scopes.dependencies.onSessionStart)
    }

    func testWhenEnabledWithNoSessionStartListener() throws {
        // Given
        config.onSessionStart = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNil(monitor.scopes.dependencies.onSessionStart)
    }

    func testWhenEnabledWithCustomEndpoint() throws {
        // Given
        let randomURL: URL = .mockRandom()
        config.customEndpoint = randomURL

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertEqual((rum.requestBuilder as? RequestBuilder)?.customIntakeURL, randomURL)
    }

    func testWhenEnabledWithNoCustomEndpoint() throws {
        // Given
        config.customEndpoint = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        XCTAssertNil((rum.requestBuilder as? RequestBuilder)?.customIntakeURL)
    }

    func testWhenEnabledWithDebugSDKArgument() throws {
        // Given
        config.sessionSampleRate = .mockRandom(min: 0, max: 100)
        config.debugSDK = true

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let crashReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(monitor.scopes.dependencies.sessionSampler.samplingRate, 100)
        XCTAssertEqual(crashReceiver?.sessionSampler.samplingRate, 100)
    }

    func testWhenEnabledWithNoDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.sessionSampleRate = random
        config.debugSDK = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        let crashReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: CrashReportReceiver.self)
        XCTAssertEqual(monitor.scopes.dependencies.sessionSampler.samplingRate, random)
        XCTAssertEqual(crashReceiver?.sessionSampler.samplingRate, random)
    }

    func testWhenEnabledWithDebugViewsArgument() {
        // Given
        config.debugViews = true

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core).debug)
    }

    func testWhenEnabledWithNoDebugViewsArgument() {
        // Given
        config.debugViews = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertFalse(RUMMonitor.shared(in: core).debug)
    }

    func testWhenEnabledWithOverwritingConfigurationTelemetrySampleRate() throws {
        // Given
        config._internal_mutation { $0.configurationTelemetrySampleRate = 42 }

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 42)
    }

    func testWhenEnabledWithNoOverwritingConfigurationTelemetrySampleRate() throws {
        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let telemetryReceiver = (rum.messageReceiver as! CombinedFeatureMessageReceiver).receivers.firstElement(of: TelemetryReceiver.self)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 20)
    }

    // MARK: - Behaviour Tests

    func testWhenEnabled_itSetsRUMContextInCore() throws {
        let core = PassthroughCoreMock()
        let applicationID: String = .mockRandom()
        let sessionID: RUMUUID = .mockRandom()

        // When
        config = RUM.Configuration(applicationID: applicationID)
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionID)
        config.sessionSampleRate = 100
        RUM.enable(with: config, in: core)

        // Then
        let context: RUMCoreContext? = try core.context.baggages["rum"]?.decode()
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.applicationID, applicationID)
        XCTAssertEqual(context?.sessionID, sessionID.toRUMDataFormat)
        XCTAssertNil(context?.viewID)
        XCTAssertNil(context?.userActionID)
    }

    func testWhenEnabled_itNotifiesInitialSessionID() {
        let core = PassthroughCoreMock()

        // Given
        let expectation = self.expectation(description: "notify initial session")
        config.onSessionStart = { sessionID, isDiscarded in
            // Then
            XCTAssertTrue(sessionID.matches(regex: .uuidRegex))
            expectation.fulfill()
        }

        // When
        RUM.enable(with: config, in: core)

        waitForExpectations(timeout: 2.5)
    }
}
