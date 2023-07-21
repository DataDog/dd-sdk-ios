/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

extension RUMFeature {
    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockAny() -> RUMFeature { .mockWith() }

    /// Mocks an instance of the feature that performs no writes to file system and does no uploads.
    static func mockWith(
        configuration: FeaturesConfiguration.RUM = .mockAny(),
        messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
    ) -> RUMFeature {
        return RUMFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: configuration,
            messageReceiver: messageReceiver
        )
    }
}

extension DatadogCoreProxy {
    func waitAndReturnRUMEventMatchers(file: StaticString = #file, line: UInt = #line) throws -> [RUMEventMatcher] {
        return try waitAndReturnEventsData(of: RUMFeature.self)
            .map { data in try RUMEventMatcher.fromJSONObjectData(data) }
    }
}

extension WebViewEventReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        dateProvider: DateProvider = SystemDateProvider(),
        commandSubscriber: RUMCommandSubscriber = GlobalRUMCommandSubscriber()
    ) -> Self {
        .init(
            dateProvider: dateProvider,
            commandSubscriber: commandSubscriber
        )
    }
}

extension CrashReportReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        applicationID: String = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        sessionSampler: Sampler = .mockKeepAll(),
        backgroundEventTrackingEnabled: Bool = true,
        uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator()
    ) -> Self {
        .init(
            applicationID: applicationID,
            dateProvider: dateProvider,
            sessionSampler: sessionSampler,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled,
            uuidGenerator: uuidGenerator
        )
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

extension RUMTelemetry {
    static func mockAny(in core: DatadogCoreProtocol) -> Self { .mockWith(core: core) }

    static func mockWith(
        core: DatadogCoreProtocol,
        dateProvider: DateProvider = SystemDateProvider(),
        configurationEventMapper: RUMTelemetryConfiguratoinMapper? = nil,
        delayedDispatcher: RUMTelemetryDelayedDispatcher? = nil,
        sampler: Sampler = .init(samplingRate: 100),
        configurationExtraSampler: Sampler = .init(samplingRate: 100)
    ) -> Self {
        .init(
            in: core,
            dateProvider: dateProvider,
            configurationEventMapper: configurationEventMapper,
            delayedDispatcher: delayedDispatcher,
            sampler: sampler,
            configurationExtraSampler: configurationExtraSampler
        )
    }
}

// MARK: - RUMDataModel Mocks

struct RUMDataModelMock: RUMDataModel, RUMSanitizableEvent {
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
    var isUserInteraction = false
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
    public static func mockAny() -> RUMStartViewCommand { mockWith() }

    public static func mockRandom() -> RUMStartViewCommand {
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
    public static func mockAny() -> RUMStopViewCommand { mockWith() }

    public static func mockRandom() -> RUMStopViewCommand {
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
    public static func mockAny() -> RUMAddCurrentViewErrorCommand { .mockWithErrorObject() }

    public static func mockRandom() -> RUMAddCurrentViewErrorCommand {
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
    public static func mockAny() -> RUMAddViewTimingCommand { .mockWith() }

    public static func mockRandom() -> RUMAddViewTimingCommand {
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

extension RUMSpanContext: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMSpanContext {
        return .mockWith()
    }

    public static func mockRandom() -> RUMSpanContext {
        return RUMSpanContext(
            traceID: .mockRandom(),
            spanID: .mockRandom(),
            samplingRate: .mockRandom()
        )
    }

    static func mockWith(
        traceID: String = .mockAny(),
        spanID: String = .mockAny(),
        samplingRate: Double = .mockAny()
    ) -> RUMSpanContext {
        return RUMSpanContext(
            traceID: traceID,
            spanID: spanID,
            samplingRate: samplingRate
        )
    }
}

extension RUMStartResourceCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMStartResourceCommand { mockWith() }

    public static func mockRandom() -> RUMStartResourceCommand {
        return .mockWith(
            resourceKey: .mockRandom(),
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            url: .mockRandom(),
            httpMethod: .mockRandom(),
            kind: .mockAny(),
            isFirstPartyRequest: .mockRandom(),
            spanContext: .init(traceID: .mockRandom(), spanID: .mockRandom(), samplingRate: .mockAny())
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
        spanContext: RUMSpanContext? = .mockAny()
    ) -> RUMStartResourceCommand {
        return RUMStartResourceCommand(
            resourceKey: resourceKey,
            time: time,
            attributes: attributes,
            url: url,
            httpMethod: httpMethod,
            kind: kind,
            spanContext: spanContext
        )
    }
}

extension RUMAddResourceMetricsCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMAddResourceMetricsCommand { mockWith() }

    public static func mockRandom() -> RUMAddResourceMetricsCommand {
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
    public static func mockAny() -> RUMStopResourceCommand { mockWith() }

    public static func mockRandom() -> RUMStopResourceCommand {
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
    public static func mockAny() -> RUMStopResourceWithErrorCommand { mockWithErrorMessage() }

    public static func mockRandom() -> RUMStopResourceWithErrorCommand {
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
    public static func mockAny() -> RUMStartUserActionCommand { mockWith() }

    public static func mockRandom() -> RUMStartUserActionCommand {
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
    public static func mockAny() -> RUMStopUserActionCommand { mockWith() }

    public static func mockRandom() -> RUMStopUserActionCommand {
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
    public static func mockAny() -> RUMAddUserActionCommand { mockWith() }

    public static func mockRandom() -> RUMAddUserActionCommand {
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
    public static func mockAny() -> RUMAddLongTaskCommand { mockWith() }

    public static func mockRandom() -> RUMAddLongTaskCommand {
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

extension RUMAddFeatureFlagEvaluationCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMAddFeatureFlagEvaluationCommand { mockWith() }

    public static func mockRandom() -> RUMAddFeatureFlagEvaluationCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            name: .mockRandom(),
            value: String.mockRandom()
        )
    }

    static func mockWith(
        time: Date = .mockAny(),
        name: String = .mockAny(),
        value: Encodable = String.mockAny()
    ) -> RUMAddFeatureFlagEvaluationCommand {
        return RUMAddFeatureFlagEvaluationCommand(
            time: time,
            name: name,
            value: value
        )
    }
}

extension RUMStopSessionCommand: AnyMockable {
    public static func mockAny() -> RUMStopSessionCommand { mockWith() }

    static func mockWith(time: Date = .mockAny()) -> RUMStopSessionCommand {
        return RUMStopSessionCommand(time: time)
    }
}

// MARK: - RUMCommand Property Mocks

extension RUMInternalErrorSource: RandomMockable {
    public static func mockRandom() -> RUMInternalErrorSource {
        return [.custom, .source, .network, .webview, .logger, .console].randomElement()!
    }
}

// MARK: - RUMContext Mocks

extension RUMUUID {
    public static func mockRandom() -> RUMUUID {
        return RUMUUID(rawValue: UUID())
    }
}

extension RUMContext {
    public static func mockAny() -> RUMContext {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        sessionID: RUMUUID = .mockRandom(),
        isSessionActive: Bool = true,
        activeViewID: RUMUUID? = nil,
        activeViewPath: String? = nil,
        activeViewName: String? = nil,
        activeUserActionID: RUMUUID? = nil
    ) -> RUMContext {
        return RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: sessionID,
            isSessionActive: true,
            activeViewID: activeViewID,
            activeViewPath: activeViewPath,
            activeViewName: activeViewName,
            activeUserActionID: activeUserActionID
        )
    }
}

extension RUMSessionState: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMSessionState {
        return mockWith()
    }

    public static func mockRandom() -> RUMSessionState {
        return .init(
            sessionUUID: .mockRandom(),
            isInitialSession: .mockRandom(),
            hasTrackedAnyView: .mockRandom(),
            didStartWithReplay: .mockRandom()
        )
    }

    static func mockWith(
        sessionUUID: UUID = .mockAny(),
        isInitialSession: Bool = .mockAny(),
        hasTrackedAnyView: Bool = .mockAny(),
        didStartWithReplay: Bool? = .mockAny()
    ) -> RUMSessionState {
        return RUMSessionState(
            sessionUUID: sessionUUID,
            isInitialSession: isInitialSession,
            hasTrackedAnyView: hasTrackedAnyView,
            didStartWithReplay: didStartWithReplay
        )
    }
}

// MARK: - RUMScope Mocks

func mockNoOpSessionListener() -> RUMSessionListener {
    return { _, _ in }
}

extension RUMScopeDependencies {
    static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    static func mockWith(
        core: DatadogCoreProtocol = NOPDatadogCore(),
        rumApplicationID: String = .mockAny(),
        sessionSampler: Sampler = .mockKeepAll(),
        backgroundEventTrackingEnabled: Bool = .mockAny(),
        frustrationTrackingEnabled: Bool = true,
        firstPartyHosts: FirstPartyHosts = .init([:]),
        eventBuilder: RUMEventBuilder = RUMEventBuilder(eventsMapper: .mockNoOp()),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        ciTest: RUMCITest? = nil,
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: @escaping RUMSessionListener = mockNoOpSessionListener()
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            core: core,
            rumApplicationID: rumApplicationID,
            sessionSampler: sessionSampler,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled,
            frustrationTrackingEnabled: frustrationTrackingEnabled,
            firstPartyHosts: firstPartyHosts,
            eventBuilder: eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator,
            ciTest: ciTest,
            vitalsReaders: vitalsReaders,
            onSessionStart: onSessionStart
        )
    }

    /// Creates new instance of `RUMScopeDependencies` by replacing individual dependencies.
    func replacing(
        rumApplicationID: String? = nil,
        sessionSampler: Sampler? = nil,
        backgroundEventTrackingEnabled: Bool? = nil,
        frustrationTrackingEnabled: Bool? = nil,
        firstPartyHosts: FirstPartyHosts? = nil,
        eventBuilder: RUMEventBuilder? = nil,
        rumUUIDGenerator: RUMUUIDGenerator? = nil,
        ciTest: RUMCITest? = nil,
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: RUMSessionListener? = nil
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            core: self.core,
            rumApplicationID: rumApplicationID ?? self.rumApplicationID,
            sessionSampler: sessionSampler ?? self.sessionSampler,
            backgroundEventTrackingEnabled: backgroundEventTrackingEnabled ?? self.backgroundEventTrackingEnabled,
            frustrationTrackingEnabled: frustrationTrackingEnabled ?? self.frustrationTrackingEnabled,
            firstPartyHosts: firstPartyHosts ?? self.firstPartyHosts,
            eventBuilder: eventBuilder ?? self.eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator ?? self.rumUUIDGenerator,
            ciTest: ciTest ?? self.ciTest,
            vitalsReaders: vitalsReaders ?? self.vitalsReaders,
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

    // swiftlint:disable:next function_default_parameter_at_end
    static func mockWith(
        isInitialSession: Bool = .mockAny(),
        parent: RUMContextProvider = RUMContextProviderMock(),
        startTime: Date = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny(),
        hasReplay: Bool? = .mockAny()
    ) -> RUMSessionScope {
        return RUMSessionScope(
            isInitialSession: isInitialSession,
            parent: parent,
            startTime: startTime,
            dependencies: dependencies,
            hasReplay: hasReplay
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
        startTime: Date = .mockAny(),
        serverTimeOffset: TimeInterval = .zero
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
            startTime: startTime,
            serverTimeOffset: serverTimeOffset
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
        serverTimeOffset: TimeInterval = .zero,
        url: String = .mockAny(),
        httpMethod: RUMMethod = .mockAny(),
        isFirstPartyResource: Bool? = nil,
        resourceKindBasedOnRequest: RUMResourceType? = nil,
        spanContext: RUMSpanContext? = .mockAny(),
        onResourceEventSent: @escaping () -> Void = {},
        onErrorEventSent: @escaping () -> Void = {}
    ) -> RUMResourceScope {
        return RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: resourceKey,
            attributes: attributes,
            startTime: startTime,
            serverTimeOffset: serverTimeOffset,
            url: url,
            httpMethod: httpMethod,
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
        serverTimeOffset: TimeInterval = .zero,
        isContinuous: Bool = .mockAny(),
        onActionEventSent: @escaping (RUMActionEvent) -> Void = { _ in }
    ) -> RUMUserActionScope {
        return RUMUserActionScope(
                parent: parent,
                dependencies: dependencies,
                name: name,
                actionType: actionType,
                attributes: attributes,
                startTime: startTime,
                serverTimeOffset: serverTimeOffset,
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

// MARK: - Dependency on Session Replay

extension Dictionary where Key == String, Value == FeatureBaggage {
    static func mockSessionReplayAttributes(hasReplay: Bool?, recordsCountByViewID: [String: Int64]? = nil) -> Self {
        return [
            SessionReplayDependency.srBaggageKey: [
                SessionReplayDependency.hasReplay: hasReplay,
                SessionReplayDependency.recordsCountByViewID: recordsCountByViewID
            ]
        ]
    }
}
