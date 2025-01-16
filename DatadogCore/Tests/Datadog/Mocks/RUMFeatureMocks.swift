/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogRUM

extension DatadogCoreProxy {
    func waitAndReturnRUMEventMatchers(file: StaticString = #file, line: UInt = #line) throws -> [RUMEventMatcher] {
        return try waitAndReturnEventsData(ofFeature: RUMFeature.name)
            .map { data in try RUMEventMatcher.fromJSONObjectData(data) }
    }
}

extension RUM.Configuration {
    static func mockAny() -> RUM.Configuration {
        return mockWith { _ in }
    }

    static func mockWith(
        applicationID: String = .mockAny(),
        mutation: (inout RUM.Configuration) -> Void
    ) -> RUM.Configuration {
        var config = RUM.Configuration(applicationID: applicationID)
        mutation(&config)
        return config
    }
}

extension WebViewEventReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        featureScope: FeatureScope = NOPFeatureScope(),
        dateProvider: DateProvider = SystemDateProvider(),
        commandSubscriber: RUMCommandSubscriber = RUMCommandSubscriberMock(),
        viewCache: ViewCache = ViewCache(dateProvider: SystemDateProvider())
    ) -> Self {
        .init(
            featureScope: featureScope,
            dateProvider: dateProvider,
            commandSubscriber: commandSubscriber,
            viewCache: viewCache
        )
    }
}

extension CrashReportReceiver: AnyMockable {
    public static func mockAny() -> Self {
        .mockWith()
    }

    static func mockWith(
        featureScope: FeatureScope = NOPFeatureScope(),
        applicationID: String = .mockAny(),
        dateProvider: DateProvider = SystemDateProvider(),
        sessionSampler: Sampler = .mockKeepAll(),
        trackBackgroundEvents: Bool = true,
        uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        eventsMapper: RUMEventsMapper = .mockNoOp()
    ) -> Self {
        .init(
            featureScope: featureScope,
            applicationID: applicationID,
            dateProvider: dateProvider,
            sessionSampler: sessionSampler,
            trackBackgroundEvents: trackBackgroundEvents,
            uuidGenerator: uuidGenerator,
            ciTest: ciTest,
            syntheticsTest: syntheticsTest,
            eventsMapper: eventsMapper
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
        viewEventMapper: RUM.ViewEventMapper? = nil,
        errorEventMapper: RUM.ErrorEventMapper? = nil,
        resourceEventMapper: RUM.ResourceEventMapper? = nil,
        actionEventMapper: RUM.ActionEventMapper? = nil,
        longTaskEventMapper: RUM.LongTaskEventMapper? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) -> RUMEventsMapper {
        return RUMEventsMapper(
            viewEventMapper: viewEventMapper,
            errorEventMapper: errorEventMapper,
            resourceEventMapper: resourceEventMapper,
            actionEventMapper: actionEventMapper,
            longTaskEventMapper: longTaskEventMapper,
            telemetry: telemetry
        )
    }
}

// MARK: - RUMCommand Mocks

/// Holds the `mockView` object so it can be weakly referenced by `RUMViewScope` mocks.
let mockView: UIViewController = createMockViewInWindow()

extension ViewIdentifier {
    static func mockViewIdentifier() -> ViewIdentifier {
        ViewIdentifier(mockView)
    }

    static func mockRandomString() -> ViewIdentifier {
        ViewIdentifier(String.mockRandom())
    }
}

struct RUMCommandMock: RUMCommand {
    var time = Date()
    var globalAttributes: [AttributeKey: AttributeValue] = [:]
    var attributes: [AttributeKey: AttributeValue] = [:]
    var canStartBackgroundView = false
    var isUserInteraction = false
    var missedEventType: SessionEndedMetric.MissedEventType? = nil
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
            identity: .mockRandomString(),
            name: .mockRandom(),
            path: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: ViewIdentifier = .mockViewIdentifier(),
        name: String = .mockAny(),
        path: String = .mockAny(),
        instrumentationType: SessionEndedMetric.ViewInstrumentationType = .manual
    ) -> RUMStartViewCommand {
        return RUMStartViewCommand(
            time: time,
            identity: identity,
            name: name,
            path: path,
            attributes: attributes,
            instrumentationType: instrumentationType
        )
    }
}

extension RUMStopViewCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMStopViewCommand { mockWith() }

    public static func mockRandom() -> RUMStopViewCommand {
        return .mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            identity: .mockRandomString()
        )
    }

    static func mockWith(
        time: Date = Date(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: ViewIdentifier = .mockViewIdentifier()
    ) -> RUMStopViewCommand {
        return RUMStopViewCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            identity: identity
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMAddCurrentViewErrorCommand {
        return RUMAddCurrentViewErrorCommand(
            time: time,
            error: error,
            source: source,
            attributes: attributes
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
            time: time,
            message: message,
            type: type,
            stack: stack,
            source: source,
            attributes: attributes
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        timingName: String = .mockAny()
    ) -> RUMAddViewTimingCommand {
        return RUMAddViewTimingCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            timingName: timingName
        )
    }
}

extension RUMSpanContext: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMSpanContext {
        return .mockWith()
    }

    public static func mockRandom() -> RUMSpanContext {
        return RUMSpanContext(
            traceID: .mock(.mockRandom(), .mockRandom()),
            spanID: .mock(.mockRandom()),
            samplingRate: .mockRandom()
        )
    }

    static func mockWith(
        traceID: TraceID = .mockAny(),
        spanID: SpanID = .mockAny(),
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
            spanContext: .init(
                traceID: .mock(.mockRandom(), .mockRandom()),
                spanID: .mock(.mockRandom()),
                samplingRate: .mockAny()
            )
        )
    }

    static func mockWith(
        resourceKey: String = .mockAny(),
        time: Date = Date(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        metrics: ResourceMetrics = .mockAny()
    ) -> RUMAddResourceMetricsCommand {
        return RUMAddResourceMetricsCommand(
            resourceKey: resourceKey,
            time: time,
            globalAttributes: globalAttributes,
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        kind: RUMResourceType = .mockAny(),
        httpStatusCode: Int? = .mockAny(),
        size: Int64? = .mockAny()
    ) -> RUMStopResourceCommand {
        return RUMStopResourceCommand(
            resourceKey: resourceKey,
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            kind: kind,
            httpStatusCode: httpStatusCode,
            size: size
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
            resourceKey: resourceKey,
            time: time,
            error: error,
            source: source,
            httpStatusCode: httpStatusCode,
            attributes: attributes
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
            resourceKey: resourceKey,
            time: time,
            message: message,
            type: type,
            source: source,
            httpStatusCode: httpStatusCode,
            attributes: attributes
        )
    }
}

extension RUMStartUserActionCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMStartUserActionCommand { mockWith() }

    public static func mockRandom() -> RUMStartUserActionCommand {
        return mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes(),
            actionType: [
                .swipe,
                .scroll,
                .custom
            ].randomElement()!,
            name: .mockRandom()
        )
    }

    static func mockWith(
        time: Date = Date(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        instrumentation: InstrumentationType = .manual,
        actionType: RUMActionType = .swipe,
        name: String = .mockAny()
    ) -> RUMStartUserActionCommand {
        return RUMStartUserActionCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            instrumentation: instrumentation,
            actionType: actionType,
            name: name
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMActionType = .swipe,
        name: String? = nil
    ) -> RUMStopUserActionCommand {
        return RUMStopUserActionCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            actionType: actionType,
            name: name
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        instrumentation: InstrumentationType = .manual,
        actionType: RUMActionType = .tap,
        name: String = .mockAny()
    ) -> RUMAddUserActionCommand {
        return RUMAddUserActionCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            instrumentation: instrumentation,
            actionType: actionType,
            name: name
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
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        duration: TimeInterval = 0.01
    ) -> RUMAddLongTaskCommand {
        return RUMAddLongTaskCommand(
            time: time,
            globalAttributes: globalAttributes,
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

struct RUMUUIDGeneratorMock: RUMUUIDGenerator {
    let uuid: UUID
    func generateUnique() -> RUMUUID { RUMUUID(rawValue: uuid) }
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

func mockNoOpSessionListener() -> RUM.SessionListener {
    return { _, _ in }
}

internal class FatalErrorContextNotifierMock: FatalErrorContextNotifying {
    var sessionState: RUMSessionState?
    var view: RUMViewEvent?
    var globalAttributes: [String: Encodable] = [:]
}

extension RUMScopeDependencies {
    static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    static func mockWith(
        featureScope: FeatureScope = NOPFeatureScope(),
        rumApplicationID: String = .mockAny(),
        sessionSampler: Sampler = .mockKeepAll(),
        trackBackgroundEvents: Bool = .mockAny(),
        trackFrustrations: Bool = true,
        firstPartyHosts: FirstPartyHosts = .init([:]),
        eventBuilder: RUMEventBuilder = RUMEventBuilder(eventsMapper: .mockNoOp()),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        backtraceReporter: BacktraceReporting = BacktraceReporterMock(backtrace: nil),
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: @escaping RUM.SessionListener = mockNoOpSessionListener(),
        viewCache: ViewCache = ViewCache(dateProvider: SystemDateProvider()),
        fatalErrorContext: FatalErrorContextNotifying = FatalErrorContextNotifierMock(),
        sessionEndedMetric: SessionEndedMetricController = SessionEndedMetricController(telemetry: NOPTelemetry(), sampleRate: 0),
        watchdogTermination: WatchdogTerminationMonitor? = nil,
        networkSettledMetricFactory: @escaping (Date, String) -> TTNSMetricTracking = {
            TTNSMetric(viewName: $1, viewStartDate: $0, resourcePredicate: TimeBasedTTNSResourcePredicate())
        },
        interactionToNextViewMetricFactory: @escaping () -> INVMetricTracking = {
            INVMetric(predicate: TimeBasedINVActionPredicate())
        }
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            featureScope: featureScope,
            rumApplicationID: rumApplicationID,
            sessionSampler: sessionSampler,
            trackBackgroundEvents: trackBackgroundEvents,
            trackFrustrations: trackFrustrations,
            firstPartyHosts: firstPartyHosts,
            eventBuilder: eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator,
            backtraceReporter: backtraceReporter,
            ciTest: ciTest,
            syntheticsTest: syntheticsTest,
            vitalsReaders: vitalsReaders,
            onSessionStart: onSessionStart,
            viewCache: viewCache,
            fatalErrorContext: fatalErrorContext,
            sessionEndedMetric: sessionEndedMetric,
            watchdogTermination: watchdogTermination,
            networkSettledMetricFactory: networkSettledMetricFactory,
            interactionToNextViewMetricFactory: interactionToNextViewMetricFactory
        )
    }

    /// Creates new instance of `RUMScopeDependencies` by replacing individual dependencies.
    func replacing(
        rumApplicationID: String? = nil,
        sessionSampler: Sampler? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackFrustrations: Bool? = nil,
        firstPartyHosts: FirstPartyHosts? = nil,
        eventBuilder: RUMEventBuilder? = nil,
        rumUUIDGenerator: RUMUUIDGenerator? = nil,
        backtraceReporter: BacktraceReporting? = nil,
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: RUM.SessionListener? = nil,
        viewCache: ViewCache? = nil,
        fatalErrorContext: FatalErrorContextNotifying? = nil,
        sessionEndedMetric: SessionEndedMetricController? = nil,
        watchdogTermination: WatchdogTerminationMonitor? = nil,
        networkSettledMetricFactory: ((Date, String) -> TTNSMetricTracking)? = nil,
        interactionToNextViewMetricFactory: (() -> INVMetricTracking)? = nil
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            featureScope: self.featureScope,
            rumApplicationID: rumApplicationID ?? self.rumApplicationID,
            sessionSampler: sessionSampler ?? self.sessionSampler,
            trackBackgroundEvents: trackBackgroundEvents ?? self.trackBackgroundEvents,
            trackFrustrations: trackFrustrations ?? self.trackFrustrations,
            firstPartyHosts: firstPartyHosts ?? self.firstPartyHosts,
            eventBuilder: eventBuilder ?? self.eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator ?? self.rumUUIDGenerator,
            backtraceReporter: backtraceReporter ?? self.backtraceReporter,
            ciTest: ciTest ?? self.ciTest,
            syntheticsTest: syntheticsTest ?? self.syntheticsTest,
            vitalsReaders: vitalsReaders ?? self.vitalsReaders,
            onSessionStart: onSessionStart ?? self.onSessionStart,
            viewCache: viewCache ?? self.viewCache,
            fatalErrorContext: fatalErrorContext ?? self.fatalErrorContext,
            sessionEndedMetric: sessionEndedMetric ?? self.sessionEndedMetric,
            watchdogTermination: watchdogTermination ?? self.watchdogTermination,
            networkSettledMetricFactory: networkSettledMetricFactory ?? self.networkSettledMetricFactory,
            interactionToNextViewMetricFactory: interactionToNextViewMetricFactory ?? self.interactionToNextViewMetricFactory
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

    // swiftlint:disable function_default_parameter_at_end
    static func mockWith(
        isInitialSession: Bool = .mockAny(),
        parent: RUMContextProvider = RUMContextProviderMock(),
        startTime: Date = .mockAny(),
        startPrecondition: RUMSessionPrecondition? = .userAppLaunch,
        context: DatadogContext = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny(),
        hasReplay: Bool? = .mockAny()
    ) -> RUMSessionScope {
        return RUMSessionScope(
            isInitialSession: isInitialSession,
            parent: parent,
            startTime: startTime,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: dependencies
        )
    }
    // swiftlint:enable function_default_parameter_at_end
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

    let viewController = UIViewController()
    object_setClass(viewController, theClass)
    mockWindow.rootViewController = viewController
    mockWindow.makeKeyAndVisible()
    return viewController
}

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
        identity: ViewIdentifier = .mockViewIdentifier(),
        path: String = .mockAny(),
        name: String = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        customTimings: [String: Int64] = randomTimings(),
        startTime: Date = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        interactionToNextViewMetric: INVMetricTracking = INVMetric(predicate: TimeBasedINVActionPredicate())
    ) -> RUMViewScope {
        return RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: dependencies,
            identity: identity,
            path: path,
            name: name,
            customTimings: customTimings,
            startTime: startTime,
            serverTimeOffset: serverTimeOffset,
            interactionToNextViewMetric: interactionToNextViewMetric
        )
    }
}

extension RUMResourceScope {
    static func mockWith(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String = .mockAny(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        url: String = .mockAny(),
        httpMethod: RUMMethod = .mockAny(),
        isFirstPartyResource: Bool? = nil,
        resourceKindBasedOnRequest: RUMResourceType? = nil,
        spanContext: RUMSpanContext? = .mockAny(),
        networkSettledMetric: TTNSMetricTracking = TTNSMetric(viewName: .mockAny(), viewStartDate: .mockAny(), resourcePredicate: TimeBasedTTNSResourcePredicate()),
        onResourceEvent: @escaping (Bool) -> Void = { _ in },
        onErrorEvent: @escaping (Bool) -> Void = { _ in }
    ) -> RUMResourceScope {
        return RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: resourceKey,
            startTime: startTime,
            serverTimeOffset: serverTimeOffset,
            url: url,
            httpMethod: httpMethod,
            resourceKindBasedOnRequest: resourceKindBasedOnRequest,
            spanContext: spanContext,
            networkSettledMetric: networkSettledMetric,
            onResourceEvent: onResourceEvent,
            onErrorEvent: onErrorEvent
        )
    }
}

extension RUMUserActionScope {
    // swiftlint:disable function_default_parameter_at_end
    static func mockWith(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies = .mockAny(),
        name: String = .mockAny(),
        actionType: RUMActionType = [.tap, .scroll, .swipe, .custom].randomElement()!,
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        isContinuous: Bool = .mockAny(),
        instrumentation: InstrumentationType = .manual,
        interactionToNextViewMetric: INVMetricTracking = INVMetric(predicate: TimeBasedINVActionPredicate()),
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
                instrumentation: instrumentation,
                interactionToNextViewMetric: interactionToNextViewMetric,
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
typealias UIKitRUMActionsPredicateMock = UIPressRUMActionsPredicateMock
#else
typealias UIKitRUMActionsPredicateMock = UITouchRUMActionsPredicateMock
#endif

class UITouchRUMActionsPredicateMock: UITouchRUMActionsPredicate {
    var resultByView: [UIView: RUMAction] = [:]
    var result: RUMAction?

    init(result: RUMAction? = nil) {
        self.result = result
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

class UIPressRUMActionsPredicateMock: UIPressRUMActionsPredicate {
    var resultByView: [UIView: RUMAction] = [:]
    var result: RUMAction?

    init(result: RUMAction? = nil) {
        self.result = result
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

class RUMActionsHandlerMock: RUMActionsHandling {
    var onSubscribe: ((RUMCommandSubscriber) -> Void)?
    var onSendEvent: ((UIApplication, UIEvent) -> Void)?
    var onViewModifierTapped: ((String, [String: any Encodable]) -> Void)?

    func publish(to subscriber: RUMCommandSubscriber) {
        onSubscribe?(subscriber)
    }

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        onSendEvent?(application, event)
    }

    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: any Encodable]) {
        onViewModifierTapped?(actionName, actionAttributes)
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
