/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@_spi(Experimental)
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

    func testWhenNotEnabled_thenRumIsEnabledIsFalse() {
        // When
        XCTAssertNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertFalse(RUM._internal.isEnabled(in: core))
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

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

    func testWhenEnabled_thenRumIsEnabledIsTrue() {
        // When
        RUM.enable(with: config, in: core)
        XCTAssertNotNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUM._internal.isEnabled(in: core))
    }

    // MARK: - Configuration Tests

    func testWhenEnabled_thenSessionSamplerIsAvailableBeforeEnableReturns() throws {
        // Given
        // This session ID is not sampled at 50%, but it is sampled at 60%:
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        config.sessionSampleRate = 60
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))

        // When
        RUM.enable(with: config, in: core)

        // Then - deliberately no `flush()` and no waiting: the sampling decision must already be resolved
        // by the time `RUM.enable()` returns, otherwise Features instrumenting a request right here (e.g.
        // WebViewTracking) get no decision at all. See RUM-17921.
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let snapshot = try XCTUnwrap(
            rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate),
            "The session sampling decision must be available synchronously, without waiting for the initial session"
        )
        XCTAssertEqual(snapshot.sessionID, RUMUUID(rawValue: sessionUUID).toRUMDataFormat)
        XCTAssertEqual(snapshot.isSampled, DeterministicSampler(uuid: sessionUUID, samplingRate: 60).isSampled)
        XCTAssertTrue(snapshot.isSampled)
    }

    func testWhenEnabledWithDebugSDK_thenSessionSamplerUsesTheOverriddenRate() throws {
        // Given
        let sessionUUID = UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!
        config.sessionSampleRate = 0
        config.debugSDK = true
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: RUMUUID(rawValue: sessionUUID))

        // When
        RUM.enable(with: config, in: core)

        // Then - `debugSDK` forces 100%, and the synchronous store must honour it like the session does
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let snapshot = try XCTUnwrap(rum.decision(for: .combinedWithSessionRate, rate: .maxSampleRate))
        XCTAssertEqual(snapshot.sessionID, RUMUUID(rawValue: sessionUUID).toRUMDataFormat)
        XCTAssertTrue(snapshot.isSampled, "A 0% configured rate must still be forced to 100% by `debugSDK`")
    }

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
        XCTAssertEqual(rum.performanceOverride?.maxFileAgeForRead, 24.hours)
        XCTAssertEqual(monitor.applicationScope.dependencies.rumApplicationID, applicationID)
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, 100)
        XCTAssertEqual(monitor.applicationScope.dependencies.sessionEndedMetric.sampleRate, 15)
        XCTAssertEqual(telemetryReceiver?.configurationExtraSampler.samplingRate, 20)
        XCTAssertEqual(crashReportReceiver?.sessionSampler.samplingRate, 100)
    }

    #if !os(watchOS)
    func testWhenEnabledWithAllInstrumentations() throws {
        // Given
        #if os(macOS)
        config.appKitViewsPredicate = UIKitRUMViewsPredicateMock()
        config.macOSActionsPredicate = MacOSRUMActionsPredicateMock()
        #else
        config.uiKitViewsPredicate = UIKitRUMViewsPredicateMock()
        config.uiKitActionsPredicate = UIKitRUMActionsPredicateMock()
        #endif
        config.swiftUIViewsPredicate = SwiftUIRUMViewsPredicateMock()
        #if !os(macOS)
        config.swiftUIActionsPredicate = SwiftUIRUMActionsPredicateMock()
        #endif
        config.longTaskThreshold = 0.5
        config.appHangThreshold = 2

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(monitor, rum.instrumentation.viewsHandler.subscriber)
        XCTAssertIdentical(monitor, (rum.instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber)
        XCTAssertIdentical(monitor, rum.instrumentation.longTasks?.subscriber)
        XCTAssertIdentical(monitor, rum.instrumentation.appHangs?.nonFatalHangsHandler.subscriber)
        #if !os(macOS)
        XCTAssertIdentical(monitor, (rum.instrumentation.memoryWarningMonitor?.reporter as? MemoryWarningReporter)?.subscriber)
        #endif
    }

    #if !os(tvOS) && !os(macOS)
    func testWhenEnabledWithEmptyFeatureFlags_scrollAndSwipeTrackingRemainsEnabled() throws {
        // Given
        config.uiKitActionsPredicate = UIKitRUMActionsPredicateMock()
        config.featureFlags = [:]

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        DDAssertActiveSwizzlings(["sendEvent:", "setDelegate:", "delegate"])
        XCTAssertNotNil(rum.instrumentation.scrollViewSwizzler)
        XCTAssertNotNil(rum.instrumentation.scrollHandler)
    }
    #endif

    func testWhenEnabledWithNoInstrumentations() throws {
        // Given
        #if os(macOS)
        config.appKitViewsPredicate = nil
        config.macOSActionsPredicate = nil
        #else
        config.uiKitViewsPredicate = nil
        config.uiKitActionsPredicate = nil
        #endif
        config.swiftUIViewsPredicate = nil
        #if !os(macOS)
        config.swiftUIActionsPredicate = nil
        #endif
        config.longTaskThreshold = nil
        config.appHangThreshold = nil
        config.trackMemoryWarnings = false

        // When
        RUM.enable(with: config, in: core)

        // Then
        let rum = try XCTUnwrap(core.get(feature: RUMFeature.self))
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertIdentical(
            monitor,
            rum.instrumentation.viewsHandler.subscriber,
            "It must always subscribe RUM monitor to `RUMViewsHandler` as it is required for SwiftUI instrumentation"
        )
        XCTAssertIdentical(
            monitor,
            (rum.instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber,
            "It must always subscribe RUM monitor to `RUMActionsHandler` as it is required for SwiftUI instrumentation"
        )
        XCTAssertNil(rum.instrumentation.longTasks)
        XCTAssertNil(rum.instrumentation.appHangs)
        XCTAssertNil(rum.instrumentation.memoryWarningMonitor)
    }
    #endif

    func testWhenEnabledWithInvalidLongTasksThreshold() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        config.longTaskThreshold = -5

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertEqual(dd.logger.errorLog?.message, "`RUM.Configuration.longTaskThreshold` cannot be less than 0s. Long Tasks monitoring will be disabled.")
    }

    func testWhenEnabledWithInvalidAppHangThreshold() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        config.appHangThreshold = .mockRandom(min: -10, max: 0.0999)

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertEqual(dd.logger.warnLog?.message, "`RUM.Configuration.appHangThreshold` cannot be less than 0.1s. A value of 0.1s will be used.")
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
        XCTAssertNotNil(monitor.applicationScope.dependencies.vitalsReaders)
    }

    func testWhenEnabledWithNoVitalsUpdateFrequency() throws {
        // Given
        config.vitalsUpdateFrequency = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertNil(monitor.applicationScope.dependencies.vitalsReaders)
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
        let eventsMapper = monitor.applicationScope.dependencies.eventBuilder.eventsMapper
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
        let eventsMapper = monitor.applicationScope.dependencies.eventBuilder.eventsMapper
        XCTAssertNil(eventsMapper.viewEventMapper)
        XCTAssertNil(eventsMapper.resourceEventMapper)
        XCTAssertNil(eventsMapper.actionEventMapper)
        XCTAssertNil(eventsMapper.errorEventMapper)
        XCTAssertNil(eventsMapper.longTaskEventMapper)
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
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, 100)
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
        XCTAssertEqual(monitor.applicationScope.dependencies.samplingRate, random)
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

    // MARK: - Remote Configuration

    func testWhenEnabled_itAppliesRemoteConfigurationOnTopOfInCodeConfiguration() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.trackBackgroundEvents = false
        core.remoteConfiguration = RemoteConfiguration(
            rum: .init(applicationId: .mockRandom(), trackBackgroundEvents: true)
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertTrue(monitor.applicationScope.dependencies.trackBackgroundEvents)
    }

    func testWhenEnabledWithNoRemoteConfiguration_itUsesInCodeConfiguration() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.trackBackgroundEvents = true
        core.remoteConfiguration = nil

        // When
        RUM.enable(with: config, in: core)

        // Then
        let monitor = try XCTUnwrap(RUMMonitor.shared(in: core) as? Monitor)
        XCTAssertTrue(monitor.applicationScope.dependencies.trackBackgroundEvents)
    }

    func testWhenEnabledWithRemoteTrackResources_itEnablesNetworkInstrumentation() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.urlSessionTracking = nil
        core.remoteConfiguration = RemoteConfiguration(
            rum: .init(applicationId: .mockRandom(), trackResources: true)
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(
            core.get(feature: NetworkInstrumentationFeature.self),
            "Remote `trackResources` must enable `NetworkInstrumentationFeature` at enable time"
        )
    }

    func testWhenEnabledWithRemoteTrace_itEnablesNetworkInstrumentation() throws {
        // Given
        config = RUM.Configuration(applicationID: .mockRandom())
        config.urlSessionTracking = nil
        core.remoteConfiguration = RemoteConfiguration(
            trace: .init(tracedHosts: [.init(host: "example.com", propagatorTypes: [])])
        )

        // When
        RUM.enable(with: config, in: core)

        // Then
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "Remote `trace` must enable `NetworkInstrumentationFeature` at enable time"
        )
        let urlSessionHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: URLSessionRUMResourcesHandler.self)
        )
        XCTAssertEqual(urlSessionHandler.distributedTracing?.firstPartyHosts.hosts, ["example.com"])
    }

    // MARK: - Behaviour Tests

    func testWhenEnabledWithTimeseries_itSendsUsageTelemetryOnlyAfterFeatureIsRegistered() throws {
        // Given
        weak var core: SingleFeatureCoreMock<RUMFeature>?
        var featureWasRegisteredWhenTelemetryReceived: Bool?
        let receiver = FeatureMessageReceiverMock { message in
            guard case .telemetry(.usage(let usage)) = message, case .timeseries = usage.event else {
                return
            }
            featureWasRegisteredWhenTelemetryReceived = core?.get(feature: RUMFeature.self) != nil
        }
        let strongCore = SingleFeatureCoreMock<RUMFeature>(messageReceiver: receiver)
        // `TimeseriesSessionCollector` keeps a long-lived reference to its feature scope, which would otherwise
        // create a core -> feature -> collector -> scope -> core retain cycle with the default `self`-as-scope.
        strongCore.featureScopeOverride = NOPFeatureScope()
        core = strongCore
        config.timeseries = .init(collectTypes: [.memory])

        // When
        RUM.enable(with: config, in: strongCore)

        // Then
        XCTAssertEqual(featureWasRegisteredWhenTelemetryReceived, true)
    }

    func testWhenEnabled_itSetsRUMContextInCore() throws {
        let core = PassthroughCoreMock()
        let applicationID: String = .mockRandom()
        let sessionID: RUMUUID = .mockRandom()

        // When
        config = RUM.Configuration(applicationID: applicationID)
        config.uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionID)
        config.sessionSampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // Then
        let context = core.context.additionalContext(ofType: RUMCoreContext.self)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.applicationID, applicationID)
        XCTAssertEqual(context?.sessionID, sessionID.toRUMDataFormat)
        XCTAssertNotNil(context?.viewID)
        XCTAssertNil(context?.userActionID)
    }

    func testWhenEnabled_itNotifiesInitialSessionID() {
        let core = PassthroughCoreMock()

        // Given
        let expectation = self.expectation(description: "notify initial session")
        config.onSessionStart = { sessionID, isDiscarded in
            // Then
            XCTAssertTrue(sessionID.matches(regex: .uuidRegex))
            XCTAssertEqual(sessionID, sessionID.lowercased())
            expectation.fulfill()
        }

        // When
        RUM.enable(with: config, in: core)

        waitForExpectations(timeout: 2.5)
    }

    // MARK: - RUM+Internal tests

    func testWhenPassedNOPCore_lateEnableUrlSessionTrackingThrows() {
        // Given
        let core = NOPDatadogCore()
        let config = RUM.Configuration.URLSessionTracking()

        // When + Then
        XCTAssertThrowsError(try RUM._internal.enableURLSessionTracking(with: config, in: core))
    }

    func testWhenRumNotEnabled_lateEnableUrlSessionTrackingThrows() {
        // Given
        let core = PassthroughCoreMock()
        let config = RUM.Configuration.URLSessionTracking()

        // When + Then
        XCTAssertThrowsError(try RUM._internal.enableURLSessionTracking(with: config, in: core))
    }

    func testLateEnableUrlSessionTracking() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        let debugSDK: Bool = .mockRandom()
        var rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.debugSDK = debugSDK
        RUM.enable(with: rumConfig, in: core)
        let hosts: Set<String> = ["datadoghq.com", "example.com", "localhost"]
        let sampleRate: Float = .mockRandom(min: 0.0, max: 1.0)
        let hostsTracing: RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing = .trace(hosts: hosts, sampleRate: sampleRate)

        let config = RUM.Configuration.URLSessionTracking(
            firstPartyHostsTracing: hostsTracing
        )

        // When
        try RUM._internal.enableURLSessionTracking(with: config, in: core)

        // Then
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let urlSessionHandler = try XCTUnwrap(feature.handlers.first as? URLSessionRUMResourcesHandler)
        XCTAssertEqual(urlSessionHandler.distributedTracing?.firstPartyHosts.hosts, hosts)
        XCTAssertEqual(urlSessionHandler.distributedTracing?.samplingRate, debugSDK ? 100.0 : sampleRate)
    }
}

#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import MachO

@MainActor
final class SwiftUIOffPublicEntryTests: XCTestCase {
    private let modes = ["default"]

    func testTrackedView_preservesLegacyCallbacksAndChildStateWhenSceneTrackingIsOff() throws {
        var traces: [[String: Any]] = []
        for mode in modes {
            let core = SwiftUIOffCore()
            let center = SwiftUIOffNotificationCenter()
            try RUM.enableOrThrow(with: configuration(mode: mode, center: center), in: core)
            let feature = try XCTUnwrap(core.get(feature: RUMFeature.self))
            let subscriber = RUMCommandSubscriberMock()
            feature.instrumentation.publish(to: subscriber)
            let driver = SwiftUIOffDriver()
            let content = SwiftUIOffChild(driver: driver)
            let expectedPath = "OffTracked/\(content.typeDescription.hashValue)"
            core.lookups = []
            var tracked: AnyView? = AnyView(content.trackRUMView(
                name: "OffTracked", attributes: ["probe": "off", "sample": 7], in: core
            ))
            let entryLookups = core.lookups
            XCTAssertEqual(entryLookups, [RUMFeature.name])
            var host: UIHostingController<SwiftUIOffRoot>? = UIHostingController(
                rootView: SwiftUIOffRoot(content: try XCTUnwrap(tracked), driver: driver)
            )
            let window = UIWindow(frame: UIScreen.main.bounds)
            let previousKey = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                driver.update = nil
                window.isHidden = true
                window.rootViewController = nil
                previousKey?.makeKey()
            }
            try awaitCondition("tracked mount") { subscriber.receivedCommands.count >= 1 && driver.states == [0] }
            let start = try XCTUnwrap(subscriber.receivedCommands.first as? RUMStartViewCommand)
            XCTAssertEqual(start.name, "OffTracked")
            XCTAssertEqual(start.path, expectedPath)
            XCTAssertEqual(start.attributes["probe"] as? String, "off")
            XCTAssertEqual(start.attributes["sample"] as? Int, 7)
            XCTAssertEqual(start.instrumentationType, .swiftui)

            try XCTUnwrap(driver.update)()
            try awaitCondition("child update") { driver.states == [0, 1] }
            XCTAssertEqual(subscriber.receivedCommands.count, 1)
            driver.visible = false
            try awaitCondition("tracked unmount") { subscriber.receivedCommands.count >= 2 && driver.disappearances == 1 }
            let stop = try XCTUnwrap(subscriber.receivedCommands.last as? RUMStopViewCommand)
            XCTAssertEqual(subscriber.receivedCommands.count, 2)
            XCTAssertEqual(stop.identity, start.identity)
            let stableCommands = subscriber.receivedCommands
            let stableStates = driver.states
            driver.update = nil
            host = nil
            window.rootViewController = nil
            tracked = nil

            let next = SwiftUIOffDriver()
            core.lookups = []
            var reconstructed: AnyView? = AnyView(SwiftUIOffChild(driver: next).trackRUMView(
                name: "OffTracked", attributes: ["probe": "off", "sample": 7], in: core
            ))
            let reconstructedLookups = core.lookups
            XCTAssertEqual(reconstructedLookups, [RUMFeature.name])
            host = UIHostingController(rootView: SwiftUIOffRoot(content: try XCTUnwrap(reconstructed), driver: next))
            window.rootViewController = host
            try awaitCondition("reconstructed mount") { subscriber.receivedCommands.count >= 3 && next.states == [0] }
            let reconstructedStart = try XCTUnwrap(subscriber.receivedCommands.last as? RUMStartViewCommand)
            XCTAssertNotEqual(reconstructedStart.identity, start.identity)
            XCTAssertEqual(reconstructedStart.name, "OffTracked")
            XCTAssertEqual(reconstructedStart.path, expectedPath)
            XCTAssertEqual(reconstructedStart.attributes["probe"] as? String, "off")
            XCTAssertEqual(reconstructedStart.attributes["sample"] as? Int, 7)
            XCTAssertEqual(reconstructedStart.instrumentationType, .swiftui)
            next.visible = false
            try awaitCondition("reconstructed unmount") { subscriber.receivedCommands.count >= 4 && next.disappearances == 1 }
            let reconstructedStop = try XCTUnwrap(subscriber.receivedCommands.last as? RUMStopViewCommand)
            XCTAssertEqual(reconstructedStop.identity, reconstructedStart.identity)
            XCTAssertEqual(subscriber.receivedCommands.count, 4)
            XCTAssertEqual(core.activations, 0)
            XCTAssertEqual(core.ownerReads, 0)
            XCTAssertEqual(core.ownerRegistrations, 0)
            XCTAssertTrue(feature.instrumentation.viewsHandler is RUMViewsHandler)
            traces.append([
                "mode": mode, "entry_lookups": entryLookups, "reconstructed_lookups": reconstructedLookups,
                "expected_path": expectedPath, "content_type": content.typeDescription,
                "stable_states": stableStates, "stable_commands": try commands(stableCommands),
                "all_commands": try commands(subscriber.receivedCommands), "reconstructed_states": next.states,
                "activations": core.activations, "owner_reads": core.ownerReads,
                "owner_registrations": core.ownerRegistrations
            ])
            next.update = nil
            window.rootViewController = nil
            host = nil
            reconstructed = nil
        }
        try attach("swiftui-off-public-entry", rows: traces)
    }

    func testMissingFeatureAndNOPCore_preserveHostedChildStateWithoutRUMCommands() throws {
        var traces: [[String: Any]] = []
        for nop in [false, true] {
            let emptyCore = SwiftUIOffCore()
            let nopCore = SwiftUIOffNOPCore()
            let core: DatadogCoreProtocol = nop ? nopCore : emptyCore
            let driver = SwiftUIOffDriver()
            let content = SwiftUIOffChild(driver: driver)
            let tracked = content.trackRUMView(name: "NoFeature", in: core)
            let lookups = nop ? nopCore.lookups : emptyCore.lookups
            XCTAssertEqual(lookups, [RUMFeature.name])
            let monitor = RUMMonitor.shared(in: core)
            XCTAssertTrue(monitor is NOPMonitor)
            var host: UIHostingController<SwiftUIOffRoot>? = UIHostingController(
                rootView: SwiftUIOffRoot(content: AnyView(tracked), driver: driver)
            )
            let window = UIWindow(frame: UIScreen.main.bounds)
            let previousKey = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                driver.update = nil
                window.isHidden = true
                window.rootViewController = nil
                previousKey?.makeKey()
            }
            try awaitCondition("NOP mount") { driver.states == [0] }
            try XCTUnwrap(driver.update)()
            try awaitCondition("NOP child update") { driver.states == [0, 1] }
            driver.visible = false
            try awaitCondition("NOP unmount") { driver.disappearances == 1 }
            XCTAssertTrue(emptyCore.registry.registeredFeatures.isEmpty)
            XCTAssertEqual(emptyCore.activations, 0)
            traces.append([
                "mode": nop ? "nop-core" : "missing-feature", "entry_lookups": lookups,
                "states": driver.states, "disappearances": driver.disappearances,
                "registered_features": emptyCore.registry.registeredFeatures.count, "nop_monitor": monitor is NOPMonitor
            ])
            window.rootViewController = nil
            host = nil
        }
        try attach("swiftui-off-nop-entry", rows: traces)
    }

    func testOffFeature_keepsLegacyObserversAndReleasesSDKCollaborators() throws {
        var traces: [[String: Any]] = []
        for mode in modes {
            let center = SwiftUIOffNotificationCenter()
            var core: SwiftUIOffCore? = SwiftUIOffCore()
            try RUM.enableOrThrow(with: configuration(mode: mode, center: center), in: try XCTUnwrap(core))
            var feature: RUMFeature? = try XCTUnwrap(core?.get(feature: RUMFeature.self))
            XCTAssertTrue(feature?.instrumentation.viewsHandler is RUMViewsHandler)
            let handlerID = ObjectIdentifier(try XCTUnwrap(feature?.instrumentation.viewsHandler as AnyObject?))
            let legacy = center.registrations.filter { $0.identity == handlerID }.compactMap(\.name)
            XCTAssertEqual(Set(legacy), Set([ApplicationNotifications.didEnterBackground, ApplicationNotifications.willEnterForeground]))
            XCTAssertEqual(legacy.count, 2)
            let forbidden = Set([
                UIScene.willConnectNotification, UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification, UIScene.didDisconnectNotification
            ])
            XCTAssertTrue(Set(center.registrations.compactMap(\.name)).isDisjoint(with: forbidden))
            XCTAssertEqual(core?.activations, 0)
            XCTAssertEqual(core?.ownerReads, 0)
            XCTAssertEqual(core?.ownerRegistrations, 0)
            weak var weakFeature = feature
            weak var weakInstrumentation = feature?.instrumentation
            weak var weakHandler = feature?.instrumentation.viewsHandler as AnyObject?
            let additions = center.registrations.map(\.snapshot)
            let counters = [
                "activations": core?.activations ?? -1, "owner_reads": core?.ownerReads ?? -1,
                "owner_registrations": core?.ownerRegistrations ?? -1
            ]
            feature = nil
            core = nil
            try awaitCondition("SDK collaborator release") {
                weakFeature == nil && weakInstrumentation == nil && weakHandler == nil
            }
            let activeHandlerObservers = center.registrations.filter { $0.identity == handlerID && !$0.removed }
            XCTAssertTrue(activeHandlerObservers.isEmpty)
            traces.append([
                "mode": mode, "legacy_names": legacy.map(\.rawValue).sorted(),
                "forbidden_scene_names": forbidden.map(\.rawValue).sorted(), "additions": additions,
                "removals": center.removals, "handoff": counters, "feature_released": weakFeature == nil,
                "instrumentation_released": weakInstrumentation == nil, "handler_released": weakHandler == nil,
                "active_handler_observers": activeHandlerObservers.count
            ])
        }
        try attach("swiftui-off-resources", rows: traces)
    }

    private func configuration(mode: String, center: NotificationCenter) -> RUM.Configuration {
        var value = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000000")
        value.uiKitViewsPredicate = nil
        value.uiKitActionsPredicate = nil
        value.swiftUIViewsPredicate = nil
        value.swiftUIActionsPredicate = nil
        value.longTaskThreshold = nil
        value.appHangThreshold = nil
        value.vitalsUpdateFrequency = nil
        value.trackWatchdogTerminations = false
        value.trackMemoryWarnings = false
        value.trackSlowFrames = false
        value.notificationCenterProvider = .init(applicationCenter: center)
        return value
    }

    private func awaitCondition(_ name: String, _ condition: @escaping () -> Bool) throws {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expected], timeout: 10)
        XCTAssertEqual(result, .completed, name)
        guard result == .completed else { throw ProgrammerError(description: "Missing positive hosting boundary: \(name)") }
    }

    private func commands(_ commands: [RUMCommand]) throws -> [[String: Any]] {
        try commands.map { command in
            if let start = command as? RUMStartViewCommand {
                return [
                    "kind": "start", "identity": try identity(start.identity), "name": start.name,
                    "path": start.path, "attributes": start.attributes, "time": start.time.timeIntervalSince1970,
                    "instrumentation": String(describing: start.instrumentationType),
                    "ownership": "legacy-process-fallback", "ownership_evidence": "source-derived-legacy-routing"
                ]
            }
            if let stop = command as? RUMStopViewCommand {
                return [
                    "kind": "stop", "identity": try identity(stop.identity), "attributes": stop.attributes,
                    "time": stop.time.timeIntervalSince1970,
                    "ownership": "legacy-process-fallback", "ownership_evidence": "source-derived-legacy-routing"
                ]
            }
            throw ProgrammerError(description: "Unexpected command in isolated manual modifier fixture")
        }
    }

    private func identity(_ value: ViewIdentifier) throws -> String {
        guard case let .key(value) = value else { throw ProgrammerError(description: "Unexpected controller identity") }
        return value
    }

    private func attach(_ family: String, rows: [[String: Any]]) throws {
        let images = (0..<_dyld_image_count()).compactMap { _dyld_get_image_name($0).map(String.init(cString:)) }
        let data = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "family": family, "terminal": true,
            "pid": ProcessInfo.processInfo.processIdentifier, "loaded_images": images, "rows": rows
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = family
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class SwiftUIOffDriver: ObservableObject {
    @Published var visible = true
    var states: [Int] = []
    var disappearances = 0
    var update: (() -> Void)?
}

private struct SwiftUIOffChild: View {
    let driver: SwiftUIOffDriver
    @State private var counter = 0
    var body: some View {
        Text("Counter \(counter)")
            .onAppear {
                driver.states.append(counter)
                driver.update = { counter += 1 }
            }
            .onChange(of: counter) { driver.states.append($0) }
            .onDisappear { driver.disappearances += 1 }
    }
}

private struct SwiftUIOffRoot: View {
    let content: AnyView
    @ObservedObject var driver: SwiftUIOffDriver
    var body: some View {
        if driver.visible { content }
    }
}

private final class SwiftUIOffCore: DatadogCoreProtocol {
    let registry = FeatureRegistrationCoreMock()
    var lookups: [String] = []
    var activations = 0
    var ownerReads = 0
    var ownerRegistrations = 0
    var remoteConfiguration: RemoteConfiguration? { nil }
    func register<T>(feature: T) throws where T: DatadogFeature { try registry.register(feature: feature) }
    func feature<T>(named name: String, type: T.Type) -> T? { lookups.append(name); return registry.feature(named: name, type: type) }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature { NOPFeatureScope() }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {}
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) {}
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
}

private final class SwiftUIOffNOPCore: NOPDatadogCore {
    var lookups: [String] = []
    override func feature<T>(named name: String, type: T.Type) -> T? {
        lookups.append(name)
        return super.feature(named: name, type: type)
    }
}

private final class SwiftUIOffNotificationCenter: NotificationCenter, @unchecked Sendable {
    final class Registration {
        weak var observer: AnyObject?
        let identity: ObjectIdentifier
        let name: Notification.Name?
        let kind: String
        var removed = false
        init(observer: AnyObject, name: Notification.Name?, kind: String) {
            self.observer = observer
            identity = ObjectIdentifier(observer)
            self.name = name
            self.kind = kind
        }
        var snapshot: [String: Any] {
            ["name": name?.rawValue ?? "<all>", "kind": kind, "removed": removed]
        }
    }
    var registrations: [Registration] = []
    var removals: [[String: Any]] = []
    override func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {
        registrations.append(Registration(observer: observer as AnyObject, name: name, kind: "selector"))
        super.addObserver(observer, selector: selector, name: name, object: object)
    }
    override func addObserver(
        forName name: Notification.Name?,
        object: Any?,
        queue: OperationQueue?,
        using block: @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        let token = super.addObserver(forName: name, object: object, queue: queue, using: block)
        registrations.append(Registration(observer: token, name: name, kind: "block"))
        return token
    }
    override func removeObserver(_ observer: Any, name: Notification.Name?, object: Any?) {
        recordRemoval(observer, name: name)
        super.removeObserver(observer, name: name, object: object)
    }
    override func removeObserver(_ observer: Any) {
        recordRemoval(observer, name: nil)
        super.removeObserver(observer)
    }
    private func recordRemoval(_ observer: Any, name: Notification.Name?) {
        let identity = ObjectIdentifier(observer as AnyObject)
        for registration in registrations where registration.identity == identity && (name == nil || registration.name == name) {
            registration.removed = true
        }
        removals.append(["name": name?.rawValue ?? "<all>"])
    }
}
#endif
