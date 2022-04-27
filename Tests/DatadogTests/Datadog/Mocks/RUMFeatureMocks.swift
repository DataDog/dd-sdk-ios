/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog
import XCTest

extension RUMFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp() -> RUMFeature {
        return RUMFeature(
            eventsMapper: .mockNoOp(),
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: .mockAny(),
            commonDependencies: .mockAny(),
            vitalCPUReader: SamplingBasedVitalReaderMock(),
            vitalMemoryReader: SamplingBasedVitalReaderMock(),
            vitalRefreshRateReader: ContinuousVitalReaderMock(),
            onSessionStart: nil
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.RUM = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> RUMFeature {
        return RUMFeature(directories: directories, configuration: configuration, commonDependencies: dependencies)
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `RUMFeature.waitAndReturnRUMEventMatchers()` to inspect and assert recorded `RUMEvents`.
    static func mockByRecordingRUMEventMatchers(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.RUM = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> RUMFeature {
        // Get the full feature mock:
        let fullFeature: RUMFeature = .mockWith(
            directories: directories,
            configuration: configuration,
            dependencies: dependencies.replacing(
                dateProvider: SystemDateProvider() // replace date provider in mocked `Feature.Storage`
            )
        )
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FeatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        // Tear down the original upload
        fullFeature.upload.flushAndTearDown()
        return RUMFeature(
            eventsMapper: fullFeature.eventsMapper,
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies,
            vitalCPUReader: SamplingBasedVitalReaderMock(),
            vitalMemoryReader: SamplingBasedVitalReaderMock(),
            vitalRefreshRateReader: ContinuousVitalReaderMock(),
            onSessionStart: configuration.onSessionStart
        )
    }

    // MARK: - Expecting RUMEvent Data

    static func waitAndReturnRUMEventMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [RUMEventMatcher] {
        guard let uploadWorker = RUMFeature.instance?.upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingRUMEventMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(batchData) }
    }
}

// MARK: - Public API Mocks

extension RUMMethod {
    static func mockAny() -> RUMMethod { .get }
}

extension RUMResourceType {
    static func mockAny() -> RUMResourceType { .image }
}

// MARK: - RUMTelemetry Mocks

extension RUMTelemetry: AnyMockable {
    static func mockAny() -> Self { .mockWith() }

    static func mockWith(
        sdkVersion: String = .mockAny(),
        applicationID: String = .mockAny(),
        source: String = .mockAnySource(),
        dateProvider: DateProvider = SystemDateProvider(),
        dateCorrector: DateCorrectorType = DateCorrectorMock()
    ) -> Self {
        .init(
            sdkVersion: sdkVersion,
            applicationID: applicationID,
            source: source,
            dateProvider: dateProvider,
            dateCorrector: dateCorrector
        )
    }
}

// MARK: - RUMDataModel Mocks

struct RUMDataModelMock: RUMDataModel, RUMSanitizableEvent, EquatableInTests {
    let attribute: String
    var usr: RUMUser?
    var context: RUMEventAttributes?
}

// MARK: - Component Mocks

extension RUMEventBuilder {
    static func mockAny() -> RUMEventBuilder {
        return RUMEventBuilder(eventsMapper: .mockNoOp())
    }
}

class RUMEventOutputMock: RUMEventOutput {
    private(set) var recordedEvents: [Any] = []

    func recordedEvents<E>(ofType type: E.Type, file: StaticString = #file, line: UInt = #line) throws -> [E] {
        return recordedEvents.compactMap { event in event as? E }
    }

    // MARK: - RUMEventOutput

    func write<Event>(event: Event) where Event: Encodable {
        recordedEvents.append(event)
    }
}

extension RUMEventsMapper {
    static func mockNoOp() -> RUMEventsMapper {
        return mockWith()
    }

    static func mockWith(
        viewEventMapper: RUMViewEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil
    ) -> RUMEventsMapper {
        return RUMEventsMapper(
            viewEventMapper: viewEventMapper,
            errorEventMapper: errorEventMapper,
            resourceEventMapper: resourceEventMapper,
            actionEventMapper: actionEventMapper,
            longTaskEventMapper: longTaskEventMapper
        )
    }
}

// MARK: - RUMCommand Mocks

struct RUMCommandMock: RUMCommand {
    var time = Date()
    var attributes: [AttributeKey: AttributeValue] = [:]
    var canStartBackgroundView = false
    var canStartApplicationLaunchView = false
}

/// Creates random `RUMCommand` from available ones.
func mockRandomRUMCommand(where predicate: (RUMCommand) -> Bool = { _ in true }) -> RUMCommand {
    let allCommands: [RUMCommand] = [
        RUMStartViewCommand.mockRandom(),
        RUMStopViewCommand.mockRandom(),
        RUMAddCurrentViewErrorCommand.mockRandom(),
        RUMAddViewTimingCommand.mockRandom(),
        RUMStartResourceCommand.mockRandom(),
        RUMAddResourceMetricsCommand.mockRandom(),
        RUMStopResourceCommand.mockRandom(),
        RUMStopResourceWithErrorCommand.mockRandom(),
        RUMStartUserActionCommand.mockRandom(),
        RUMStopUserActionCommand.mockRandom(),
        RUMAddUserActionCommand.mockRandom(),
        RUMAddLongTaskCommand.mockRandom(),
    ]
    return allCommands.filter(predicate).randomElement()!
}

extension RUMCommand {
    func replacing(time: Date? = nil, attributes: [AttributeKey: AttributeValue]? = nil) -> RUMCommand {
        var command = self
        command.time = time ?? command.time
        command.attributes = attributes ?? command.attributes
        return command
    }
}

extension RUMStartViewCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStartViewCommand { mockWith() }

    static func mockRandom() -> RUMStartViewCommand {
        return .mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            identity: String.mockRandom(),
            name: .mockRandom(),
            path: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: RUMViewIdentifiable = mockView,
        name: String = .mockAny(),
        path: String? = nil
    ) -> RUMStartViewCommand {
        return RUMStartViewCommand(
            time: time,
            identity: identity,
            name: name,
            path: path,
            attributes: attributes
        )
    }
}

extension RUMStopViewCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStopViewCommand { mockWith() }

    static func mockRandom() -> RUMStopViewCommand {
        return .mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            identity: String.mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: RUMViewIdentifiable = mockView
    ) -> RUMStopViewCommand {
        return RUMStopViewCommand(
            time: time, attributes: attributes, identity: identity
        )
    }
}

extension RUMAddCurrentViewErrorCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMAddCurrentViewErrorCommand { .mockWithErrorObject() }

    static func mockRandom() -> RUMAddCurrentViewErrorCommand {
        if Bool.random() {
            return .mockWithErrorObject(
                time: .mockRandomInThePast(),
                error: ErrorMock(.mockRandom()),
                source: .mockRandom(),
                attributes: mockRandomAttributes()
            )
        } else {
            return .mockWithErrorMessage(
                time: .mockRandomInThePast(),
                message: .mockRandom(),
                type: .mockRandom(),
                source: .mockRandom(),
                stack: .mockRandom(),
                attributes: mockRandomAttributes()
            )
        }
    }

    static func mockWithErrorObject(
        time: Date = Date(),
        error: Error = ErrorMock(),
        source: RUMInternalErrorSource = .source,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMAddCurrentViewErrorCommand {
        return RUMAddCurrentViewErrorCommand(
            time: time, error: error, source: source, attributes: attributes
        )
    }

    static func mockWithErrorMessage(
        time: Date = Date(),
        message: String = .mockAny(),
        type: String? = .mockAny(),
        source: RUMInternalErrorSource = .source,
        stack: String? = "Foo.swift:10",
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMAddCurrentViewErrorCommand {
        return RUMAddCurrentViewErrorCommand(
            time: time, message: message, type: type, stack: stack, source: source, attributes: attributes
        )
    }
}

extension RUMAddViewTimingCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMAddViewTimingCommand { .mockWith() }

    static func mockRandom() -> RUMAddViewTimingCommand {
        return .mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            timingName: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        timingName: String = .mockAny()
    ) -> RUMAddViewTimingCommand {
        return RUMAddViewTimingCommand(
            time: time, attributes: attributes, timingName: timingName
        )
    }
}

extension RUMStartResourceCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStartResourceCommand { mockWith() }

    static func mockRandom() -> RUMStartResourceCommand {
        return .mockWith(
            resourceKey: .mockRandom(),
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            url: .mockRandom(),
            httpMethod: .mockRandom(),
            kind: .mockAny(),
            isFirstPartyRequest: .mockRandom(),
            spanContext: .init(traceID: .mockRandom(), spanID: .mockRandom())
        )
    }

    static func mockWith(
        resourceKey: String = .mockAny(),
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        url: String = .mockAny(),
        httpMethod: RUMMethod = .mockAny(),
        kind: RUMResourceType = .mockAny(),
        isFirstPartyRequest: Bool = .mockAny(),
        spanContext: RUMSpanContext? = nil
    ) -> RUMStartResourceCommand {
        return RUMStartResourceCommand(
            resourceKey: resourceKey,
            time: time,
            attributes: attributes,
            url: url,
            httpMethod: httpMethod,
            kind: kind,
            isFirstPartyRequest: isFirstPartyRequest,
            spanContext: spanContext
        )
    }
}

extension RUMAddResourceMetricsCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMAddResourceMetricsCommand { mockWith() }

    static func mockRandom() -> RUMAddResourceMetricsCommand {
        return mockWith(
            resourceKey: .mockRandom(),
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            metrics: .mockAny()
        )
    }

    static func mockWith(
        resourceKey: String = .mockAny(),
        time: Date = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        metrics: ResourceMetrics = .mockAny()
    ) -> RUMAddResourceMetricsCommand {
        return RUMAddResourceMetricsCommand(
            resourceKey: resourceKey,
            time: time,
            attributes: attributes,
            metrics: metrics
        )
    }
}

extension RUMStopResourceCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStopResourceCommand { mockWith() }

    static func mockRandom() -> RUMStopResourceCommand {
        return mockWith(
            resourceKey: .mockRandom(),
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            kind: [.native, .image, .font, .other].randomElement()!,
            httpStatusCode: .mockRandom(),
            size: .mockRandom()
        )
    }

    static func mockWith(
        resourceKey: String = .mockAny(),
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        kind: RUMResourceType = .mockAny(),
        httpStatusCode: Int? = .mockAny(),
        size: Int64? = .mockAny()
    ) -> RUMStopResourceCommand {
        return RUMStopResourceCommand(
            resourceKey: resourceKey, time: time, attributes: attributes, kind: kind, httpStatusCode: httpStatusCode, size: size
        )
    }
}

extension RUMStopResourceWithErrorCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStopResourceWithErrorCommand { mockWithErrorMessage() }

    static func mockRandom() -> RUMStopResourceWithErrorCommand {
        if Bool.random() {
            return mockWithErrorObject(
                resourceKey: .mockRandom(),
                time: .mockRandomInThePast(),
                error: ErrorMock(.mockRandom()),
                source: .mockRandom(),
                httpStatusCode: .mockRandom(),
                attributes: mockRandomAttributes()
            )
        } else {
            return mockWithErrorMessage(
                resourceKey: .mockRandom(),
                time: .mockRandomInThePast(),
                message: .mockRandom(),
                type: .mockRandom(),
                source: .mockRandom(),
                httpStatusCode: .mockRandom(),
                attributes: mockRandomAttributes()
            )
        }
    }

    static func mockWithErrorObject(
        resourceKey: String = .mockAny(),
        time: Date = Date(),
        error: Error = ErrorMock(),
        source: RUMInternalErrorSource = .source,
        httpStatusCode: Int? = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMStopResourceWithErrorCommand {
        return RUMStopResourceWithErrorCommand(
            resourceKey: resourceKey, time: time, error: error, source: source, httpStatusCode: httpStatusCode, attributes: attributes
        )
    }

    static func mockWithErrorMessage(
        resourceKey: String = .mockAny(),
        time: Date = Date(),
        message: String = .mockAny(),
        type: String? = .mockAny(),
        source: RUMInternalErrorSource = .source,
        httpStatusCode: Int? = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMStopResourceWithErrorCommand {
        return RUMStopResourceWithErrorCommand(
            resourceKey: resourceKey, time: time, message: message, type: type, source: source, httpStatusCode: httpStatusCode, attributes: attributes
        )
    }
}

extension RUMStartUserActionCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStartUserActionCommand { mockWith() }

    static func mockRandom() -> RUMStartUserActionCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            actionType: [.swipe, .scroll, .custom].randomElement()!,
            name: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .swipe,
        name: String = .mockAny()
    ) -> RUMStartUserActionCommand {
        return RUMStartUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
        )
    }
}

extension RUMStopUserActionCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMStopUserActionCommand { mockWith() }

    static func mockRandom() -> RUMStopUserActionCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            actionType: [.swipe, .scroll, .custom].randomElement()!,
            name: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .swipe,
        name: String? = nil
    ) -> RUMStopUserActionCommand {
        return RUMStopUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
        )
    }
}

extension RUMAddUserActionCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMAddUserActionCommand { mockWith() }

    static func mockRandom() -> RUMAddUserActionCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            actionType: [.tap, .custom].randomElement()!,
            name: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .tap,
        name: String = .mockAny()
    ) -> RUMAddUserActionCommand {
        return RUMAddUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
        )
    }
}

extension RUMAddLongTaskCommand: AnyMockable, RandomMockable {
    static func mockAny() -> RUMAddLongTaskCommand { mockWith() }

    static func mockRandom() -> RUMAddLongTaskCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            duration: .mockRandom(min: 0.01, max: 1)
        )
    }

    static func mockWith(
        time: Date = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        duration: TimeInterval = 0.01
    ) -> RUMAddLongTaskCommand {
        return RUMAddLongTaskCommand(
            time: time,
            attributes: attributes,
            duration: duration
        )
    }
}

// MARK: - RUMCommand Property Mocks

extension RUMInternalErrorSource: RandomMockable {
    static func mockRandom() -> RUMInternalErrorSource {
        return [.custom, .source, .network, .webview, .logger, .console].randomElement()!
    }
}

// MARK: - RUMContext Mocks

extension RUMUUID {
    static func mockRandom() -> RUMUUID {
        return RUMUUID(rawValue: UUID())
    }
}

extension RUMContext {
    static func mockAny() -> RUMContext {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        sessionID: RUMUUID = .mockRandom(),
        activeViewID: RUMUUID? = nil,
        activeViewPath: String? = nil,
        activeViewName: String? = nil,
        activeUserActionID: RUMUUID? = nil
    ) -> RUMContext {
        return RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: sessionID,
            activeViewID: activeViewID,
            activeViewPath: activeViewPath,
            activeViewName: activeViewName,
            activeUserActionID: activeUserActionID
        )
    }
}

extension RUMSessionState: AnyMockable, RandomMockable {
    static func mockAny() -> RUMSessionState {
        return mockWith()
    }

    static func mockRandom() -> RUMSessionState {
        return .init(sessionUUID: .mockRandom(), isInitialSession: .mockRandom(), hasTrackedAnyView: .mockRandom())
    }

    static func mockWith(
        sessionUUID: UUID = .mockAny(),
        isInitialSession: Bool = .mockAny(),
        hasTrackedAnyView: Bool = .mockAny()
    ) -> RUMSessionState {
        return RUMSessionState(sessionUUID: sessionUUID, isInitialSession: isInitialSession, hasTrackedAnyView: hasTrackedAnyView)
    }
}

// MARK: - RUMScope Mocks

internal struct NoOpRUMViewUpdatesThrottler: RUMViewUpdatesThrottlerType {
    func accept(event: RUMViewEvent) -> Bool {
        return true // always send view update
    }
}

func mockNoOpSessionListerner() -> RUMSessionListener {
    return { _, _ in }
}

extension RUMScopeDependencies {
    static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        sessionSampler: Sampler = .mockKeepAll(),
        sdkInitDate: Date = .mockAny(),
        backgroundEventTrackingEnabled: Bool = .mockAny(),
        appStateListener: AppStateListening = AppStateListenerMock.mockAny(),
        userInfoProvider: RUMUserInfoProvider = RUMUserInfoProvider(userInfoProvider: .mockAny()),
        launchTimeProvider: LaunchTimeProviderType = LaunchTimeProviderMock.mockAny(),
        connectivityInfoProvider: RUMConnectivityInfoProvider = RUMConnectivityInfoProvider(
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: nil),
            carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: nil)
        ),
        serviceName: String = .mockAny(),
        applicationVersion: String = .mockAny(),
        sdkVersion: String = .mockAny(),
        source: String = "ios",
        eventBuilder: RUMEventBuilder = RUMEventBuilder(eventsMapper: .mockNoOp()),
        eventOutput: RUMEventOutput = RUMEventOutputMock(),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        dateCorrector: DateCorrectorType = DateCorrectorMock(),
        crashContextIntegration: RUMWithCrashContextIntegration? = nil,
        ciTest: RUMCITest? = nil,
        viewUpdatesThrottlerFactory: @escaping () -> RUMViewUpdatesThrottlerType = { NoOpRUMViewUpdatesThrottler() },
        onSessionStart: @escaping RUMSessionListener = mockNoOpSessionListerner()
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            rumApplicationID: rumApplicationID,
            sessionSampler: sessionSampler,
            sdkInitDate: sdkInitDate,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled,
            appStateListener: appStateListener,
            userInfoProvider: userInfoProvider,
            launchTimeProvider: launchTimeProvider,
            connectivityInfoProvider: connectivityInfoProvider,
            serviceName: serviceName,
            applicationVersion: applicationVersion,
            sdkVersion: sdkVersion,
            source: source,
            eventBuilder: eventBuilder,
            eventOutput: eventOutput,
            rumUUIDGenerator: rumUUIDGenerator,
            dateCorrector: dateCorrector,
            crashContextIntegration: crashContextIntegration,
            ciTest: ciTest,
            viewUpdatesThrottlerFactory: viewUpdatesThrottlerFactory,
            vitalCPUReader: SamplingBasedVitalReaderMock(),
            vitalMemoryReader: SamplingBasedVitalReaderMock(),
            vitalRefreshRateReader: ContinuousVitalReaderMock(),
            onSessionStart: onSessionStart
        )
    }

    /// Creates new instance of `RUMScopeDependencies` by replacing individual dependencies.
    func replacing(
        rumApplicationID: String? = nil,
        sessionSampler: Sampler? = nil,
        sdkInitDate: Date? = nil,
        backgroundEventTrackingEnabled: Bool? = nil,
        appStateListener: AppStateListening? = nil,
        userInfoProvider: RUMUserInfoProvider? = nil,
        launchTimeProvider: LaunchTimeProviderType? = nil,
        connectivityInfoProvider: RUMConnectivityInfoProvider? = nil,
        serviceName: String? = nil,
        applicationVersion: String? = nil,
        sdkVersion: String? = nil,
        source: String? = nil,
        eventBuilder: RUMEventBuilder? = nil,
        eventOutput: RUMEventOutput? = nil,
        rumUUIDGenerator: RUMUUIDGenerator? = nil,
        dateCorrector: DateCorrectorType? = nil,
        crashContextIntegration: RUMWithCrashContextIntegration? = nil,
        ciTest: RUMCITest? = nil,
        viewUpdatesThrottlerFactory: (() -> RUMViewUpdatesThrottlerType)? = nil,
        onSessionStart: RUMSessionListener? = nil
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            rumApplicationID: rumApplicationID ?? self.rumApplicationID,
            sessionSampler: sessionSampler ?? self.sessionSampler,
            sdkInitDate: sdkInitDate ?? self.sdkInitDate,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled ?? self.backgroundEventTrackingEnabled,
            appStateListener: appStateListener ?? self.appStateListener,
            userInfoProvider: userInfoProvider ?? self.userInfoProvider,
            launchTimeProvider: launchTimeProvider ?? self.launchTimeProvider,
            connectivityInfoProvider: connectivityInfoProvider ?? self.connectivityInfoProvider,
            serviceName: serviceName ?? self.serviceName,
            applicationVersion: applicationVersion ?? self.applicationVersion,
            sdkVersion: sdkVersion ?? self.sdkVersion,
            source: source ?? self.source,
            eventBuilder: eventBuilder ?? self.eventBuilder,
            eventOutput: eventOutput ?? self.eventOutput,
            rumUUIDGenerator: rumUUIDGenerator ?? self.rumUUIDGenerator,
            dateCorrector: dateCorrector ?? self.dateCorrector,
            crashContextIntegration: crashContextIntegration ?? self.crashContextIntegration,
            ciTest: ciTest ?? self.ciTest,
            viewUpdatesThrottlerFactory: viewUpdatesThrottlerFactory ?? self.viewUpdatesThrottlerFactory,
            vitalCPUReader: SamplingBasedVitalReaderMock(),
            vitalMemoryReader: SamplingBasedVitalReaderMock(),
            vitalRefreshRateReader: ContinuousVitalReaderMock(),
            onSessionStart: onSessionStart ?? self.onSessionStart
        )
    }
}

extension RUMApplicationScope {
    static func mockAny() -> RUMApplicationScope {
        return RUMApplicationScope(dependencies: .mockAny())
    }
}

extension RUMSessionScope {
    static func mockAny() -> RUMSessionScope {
        return mockWith()
    }

    static func mockWith(
        isInitialSession: Bool = .mockAny(),
        parent: RUMContextProvider = RUMContextProviderMock(),
        startTime: Date = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny()
    ) -> RUMSessionScope {
        return RUMSessionScope(
            isInitialSession: isInitialSession,
            parent: parent,
            startTime: startTime,
            dependencies: dependencies
        )
    }
}

private let mockWindow = UIWindow(frame: .zero)

func createMockViewInWindow() -> UIViewController {
    let viewController = UIViewController()
    mockWindow.rootViewController = viewController
    mockWindow.makeKeyAndVisible()
    return viewController
}

/// Creates an instance of `UIViewController` subclass with a given name.
func createMockView(viewControllerClassName: String) -> UIViewController {
    var theClass: AnyClass! // swiftlint:disable:this implicitly_unwrapped_optional

    if let existingClass = objc_lookUpClass(viewControllerClassName) {
        theClass = existingClass
    } else {
        let newClass: AnyClass = objc_allocateClassPair(UIViewController.classForCoder(), viewControllerClassName, 0)!
        objc_registerClassPair(newClass)
        theClass = newClass
    }

    let viewController = theClass.alloc() as! UIViewController
    mockWindow.rootViewController = viewController
    mockWindow.makeKeyAndVisible()
    return viewController
}

/// Holds the `mockView` object so it can be weakly referenced by `RUMViewScope` mocks.
let mockView: UIViewController = createMockViewInWindow()

extension RUMViewScope {
    static func mockAny() -> RUMViewScope {
        return mockWith()
    }

    static func randomTimings() -> [String: Int64] {
        var timings: [String: Int64] = [:]
        (0..<10).forEach { index in timings["timing\(index)"] = .mockRandom() }
        return timings
    }

    static func mockWith(
        isInitialView: Bool = false,
        parent: RUMContextProvider = RUMContextProviderMock(),
        dependencies: RUMScopeDependencies = .mockAny(),
        identity: RUMViewIdentifiable = mockView,
        path: String = .mockAny(),
        name: String = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        customTimings: [String: Int64] = randomTimings(),
        startTime: Date = .mockAny()
    ) -> RUMViewScope {
        return RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: dependencies,
            identity: identity,
            path: path,
            name: name,
            attributes: attributes,
            customTimings: customTimings,
            startTime: startTime
        )
    }
}

extension RUMResourceScope {
    static func mockWith(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny(),
        dateCorrection: DateCorrection = .zero,
        url: String = .mockAny(),
        httpMethod: RUMMethod = .mockAny(),
        isFirstPartyResource: Bool? = nil,
        resourceKindBasedOnRequest: RUMResourceType? = nil,
        spanContext: RUMSpanContext? = nil,
        onResourceEventSent: @escaping () -> Void = {},
        onErrorEventSent: @escaping () -> Void = {}
    ) -> RUMResourceScope {
        return RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: resourceKey,
            attributes: attributes,
            startTime: startTime,
            dateCorrection: dateCorrection,
            url: url,
            httpMethod: httpMethod,
            isFirstPartyResource: isFirstPartyResource,
            resourceKindBasedOnRequest: resourceKindBasedOnRequest,
            spanContext: spanContext,
            onResourceEventSent: onResourceEventSent,
            onErrorEventSent: onErrorEventSent
        )
    }
}

extension RUMUserActionScope {
    // swiftlint:disable function_default_parameter_at_end
    static func mockWith(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies = .mockAny(),
        name: String = .mockAny(),
        actionType: RUMUserActionType = [.tap, .scroll, .swipe, .custom].randomElement()!,
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny(),
        dateCorrection: DateCorrection,
        isContinuous: Bool = .mockAny(),
        onActionEventSent: @escaping () -> Void = {}
    ) -> RUMUserActionScope {
        return RUMUserActionScope(
                parent: parent,
                dependencies: dependencies,
                name: name,
                actionType: actionType,
                attributes: attributes,
                startTime: startTime,
                dateCorrection: dateCorrection,
                isContinuous: isContinuous,
                onActionEventSent: onActionEventSent
        )
    }
    // swiftlint:enable function_default_parameter_at_end
}

class RUMContextProviderMock: RUMContextProvider {
    init(context: RUMContext = .mockAny()) {
        self.context = context
    }

    var context: RUMContext
}

// MARK: - Auto Instrumentation Mocks

class RUMCommandSubscriberMock: RUMCommandSubscriber {
    var onCommandReceived: ((RUMCommand) -> Void)?
    var receivedCommands: [RUMCommand] = []
    var lastReceivedCommand: RUMCommand? { receivedCommands.last }

    func process(command: RUMCommand) {
        receivedCommands.append(command)
        onCommandReceived?(command)
    }
}

class UIKitRUMViewsPredicateMock: UIKitRUMViewsPredicate {
    var resultByViewController: [UIViewController: RUMView] = [:]
    var result: RUMView?

    init(result: RUMView? = nil) {
        self.result = result
    }

    func rumView(for viewController: UIViewController) -> RUMView? {
        return resultByViewController[viewController] ?? result
    }
}

class UIKitRUMViewsHandlerMock: UIViewControllerHandler {
    var onSubscribe: ((RUMCommandSubscriber) -> Void)?
    var notifyViewDidAppear: ((UIViewController, Bool) -> Void)?
    var notifyViewDidDisappear: ((UIViewController, Bool) -> Void)?

    func publish(to subscriber: RUMCommandSubscriber) {
        onSubscribe?(subscriber)
    }

    func notify_viewDidAppear(viewController: UIViewController, animated: Bool) {
        notifyViewDidAppear?(viewController, animated)
    }

    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool) {
        notifyViewDidDisappear?(viewController, animated)
    }
}

#if os(tvOS)
typealias UIKitRUMUserActionsPredicateMock = UIPressRUMUserActionsPredicateMock
#else
typealias UIKitRUMUserActionsPredicateMock = UITouchRUMUserActionsPredicateMock
#endif

class UITouchRUMUserActionsPredicateMock: UITouchRUMUserActionsPredicate {
    var resultByView: [UIView: RUMAction] = [:]
    var result: RUMAction?

    init(result: RUMAction? = nil) {
        self.result = result
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

class UIPressRUMUserActionsPredicateMock: UIPressRUMUserActionsPredicate {
    var resultByView: [UIView: RUMAction] = [:]
    var result: RUMAction?

    init(result: RUMAction? = nil) {
        self.result = result
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

class UIKitRUMUserActionsHandlerMock: UIEventHandler {
    var onSubscribe: ((RUMCommandSubscriber) -> Void)?
    var onSendEvent: ((UIApplication, UIEvent) -> Void)?

    func publish(to subscriber: RUMCommandSubscriber) {
        onSubscribe?(subscriber)
    }

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        onSendEvent?(application, event)
    }
}

class SamplingBasedVitalReaderMock: SamplingBasedVitalReader {
    var vitalData: Double?

    func readVitalData() -> Double? {
        return vitalData
    }
}

class ContinuousVitalReaderMock: ContinuousVitalReader {
    var vitalInfo = VitalInfo() {
        didSet {
            publishers.forEach {
                $0.publishAsync(vitalInfo)
            }
        }
    }
    var publishers = [VitalPublisher]()

    func register(_ valuePublisher: VitalPublisher) {
        publishers.append(valuePublisher)
    }

    func unregister(_ valuePublisher: VitalPublisher) {
        publishers.removeAll { existingPublisher in
            return existingPublisher === valuePublisher
        }
    }
}
