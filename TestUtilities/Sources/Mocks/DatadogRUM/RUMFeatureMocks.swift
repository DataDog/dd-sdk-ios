/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import UIKit
@testable import DatadogRUM

extension RUM.Configuration {
    public static func mockAny() -> RUM.Configuration {
        .init(applicationID: .mockAny())
    }

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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
    public static func mockAny() -> RUMMethod { .get }
}

extension RUMResourceType {
    public static func mockAny() -> RUMResourceType { .image }
}

// MARK: - RUMDataModel Mocks

public struct RUMDataModelMock: RUMDataModel, RUMSanitizableEvent {
    let attribute: String
    public var usr: RUMUser?
    public var context: RUMEventAttributes?

    public init(attribute: String, usr: RUMUser? = nil, context: RUMEventAttributes? = nil) {
        self.attribute = attribute
        self.usr = usr
        self.context = context
    }
}

/// Creates random RUM event.
public func randomRUMEvent() -> RUMDataModel {
    // swiftlint:disable opening_brace
    return oneOf([
        { RUMViewEvent.mockRandom() },
        { RUMActionEvent.mockRandom() },
        { RUMResourceEvent.mockRandom() },
        { RUMErrorEvent.mockRandom() },
        { RUMLongTaskEvent.mockRandom() },
    ])
    // swiftlint:enable opening_brace
}

// MARK: - Component Mocks

extension RUMEventBuilder {
    public static func mockAny() -> RUMEventBuilder {
        return RUMEventBuilder(eventsMapper: .mockNoOp())
    }
}

extension RUMEventsMapper {
    public static func mockNoOp() -> RUMEventsMapper {
        return mockWith()
    }

    public static func mockWith(
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
public let mockView: UIViewController = createMockViewInWindow()

extension ViewIdentifier {
    public static func mockViewIdentifier() -> ViewIdentifier {
        ViewIdentifier(mockView)
    }

    public static func mockRandomString() -> ViewIdentifier {
        ViewIdentifier(String.mockRandom())
    }
}

public struct RUMCommandMock: RUMCommand {
    public var time: Date
    public var globalAttributes: [AttributeKey: AttributeValue]
    public var attributes: [AttributeKey: AttributeValue]
    public var canStartBackgroundView: Bool
    public var isUserInteraction: Bool
    public var missedEventType: SessionEndedMetric.MissedEventType? = nil

    public init(
        time: Date = Date(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:],
        canStartBackgroundView: Bool = false,
        isUserInteraction: Bool = false
    ) {
        self.time = time
        self.globalAttributes = globalAttributes
        self.attributes = attributes
        self.canStartBackgroundView = canStartBackgroundView
        self.isUserInteraction = isUserInteraction
    }
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWithErrorObject(
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

    public static func mockWithErrorMessage(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWithErrorObject(
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

    public static func mockWithErrorMessage(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(
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

    public static func mockWith(time: Date = .mockAny()) -> RUMStopSessionCommand {
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

extension RUMUUID: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMUUID {
        RUMUUID(rawValue: UUID())
    }

    public static func mockRandom() -> RUMUUID {
        RUMUUID(rawValue: UUID())
    }
}

public class RUMUUIDGeneratorMock: RUMUUIDGenerator {
    public var uuid: RUMUUID
    public func generateUnique() -> RUMUUID { uuid }

    public init(uuid: RUMUUID) {
        self.uuid = uuid
    }
}

extension RUMContext {
    public static func mockAny() -> RUMContext {
        return mockWith()
    }

    public static func mockWith(
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

    public static func mockWith(
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

public func mockNoOpSessionListener() -> RUM.SessionListener {
    return { _, _ in }
}

public class FatalErrorContextNotifierMock: FatalErrorContextNotifying {
    public var sessionState: RUMSessionState?
    public var view: RUMViewEvent?
    public var globalAttributes: [String: Encodable] = [:]

    public init() {}
}

extension RUMScopeDependencies {
    public static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    public static func mockWith(
        featureScope: FeatureScope = NOPFeatureScope(),
        rumApplicationID: String = .mockAny(),
        sessionSampler: Sampler = .mockKeepAll(),
        trackBackgroundEvents: Bool = .mockAny(),
        trackFrustrations: Bool = true,
        hasAppHangsEnabled: Bool = true,
        firstPartyHosts: FirstPartyHosts = .init([:]),
        eventBuilder: RUMEventBuilder = RUMEventBuilder(eventsMapper: .mockNoOp()),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        backtraceReporter: BacktraceReporting = BacktraceReporterMock(backtrace: nil),
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        renderLoopObserver: RenderLoopObserver? = nil,
        viewHitchesMetricFactory: @escaping () -> (RenderLoopReader & ViewHitchesMetric)? = { ViewHitchesMock.mockAny() },
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: @escaping RUM.SessionListener = mockNoOpSessionListener(),
        viewCache: ViewCache = ViewCache(dateProvider: SystemDateProvider()),
        fatalErrorContext: FatalErrorContextNotifying = FatalErrorContextNotifierMock(),
        sessionEndedMetric: SessionEndedMetricController = SessionEndedMetricController(telemetry: NOPTelemetry(), sampleRate: 0),
        viewEndedMetricFactory: @escaping () -> ViewEndedMetricController = {
            ViewEndedMetricController(tnsPredicateType: .custom, invPredicateType: .custom, telemetry: NOPTelemetry(), sampleRate: 0)
        },
        watchdogTermination: WatchdogTerminationMonitor? = nil,
        networkSettledMetricFactory: @escaping (Date, String) -> TNSMetricTracking = {
            TNSMetric(viewName: $1, viewStartDate: $0, resourcePredicate: TimeBasedTNSResourcePredicate())
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
            hasAppHangsEnabled: hasAppHangsEnabled,
            firstPartyHosts: firstPartyHosts,
            eventBuilder: eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator,
            backtraceReporter: backtraceReporter,
            ciTest: ciTest,
            syntheticsTest: syntheticsTest,
            renderLoopObserver: renderLoopObserver,
            viewHitchesMetricFactory: viewHitchesMetricFactory,
            vitalsReaders: vitalsReaders,
            onSessionStart: onSessionStart,
            viewCache: viewCache,
            fatalErrorContext: fatalErrorContext,
            sessionEndedMetric: sessionEndedMetric,
            viewEndedMetricFactory: viewEndedMetricFactory,
            watchdogTermination: watchdogTermination,
            networkSettledMetricFactory: networkSettledMetricFactory,
            interactionToNextViewMetricFactory: interactionToNextViewMetricFactory
        )
    }

    /// Creates new instance of `RUMScopeDependencies` by replacing individual dependencies.
    public func replacing(
        rumApplicationID: String? = nil,
        sessionSampler: Sampler? = nil,
        trackBackgroundEvents: Bool? = nil,
        trackFrustrations: Bool? = nil,
        hasAppHangsEnabled: Bool? = nil,
        firstPartyHosts: FirstPartyHosts? = nil,
        eventBuilder: RUMEventBuilder? = nil,
        rumUUIDGenerator: RUMUUIDGenerator? = nil,
        backtraceReporter: BacktraceReporting? = nil,
        ciTest: RUMCITest? = nil,
        syntheticsTest: RUMSyntheticsTest? = nil,
        renderLoopObserver: RenderLoopObserver? = nil,
        viewHitchesMetricFactory: (() -> RenderLoopReader & ViewHitchesMetric)? = nil,
        vitalsReaders: VitalsReaders? = nil,
        onSessionStart: RUM.SessionListener? = nil,
        viewCache: ViewCache? = nil,
        fatalErrorContext: FatalErrorContextNotifying? = nil,
        sessionEndedMetric: SessionEndedMetricController? = nil,
        viewEndedMetricFactory: (() -> ViewEndedMetricController)? = nil,
        watchdogTermination: WatchdogTerminationMonitor? = nil,
        networkSettledMetricFactory: ((Date, String) -> TNSMetricTracking)? = nil,
        interactionToNextViewMetricFactory: (() -> INVMetricTracking)? = nil
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            featureScope: self.featureScope,
            rumApplicationID: rumApplicationID ?? self.rumApplicationID,
            sessionSampler: sessionSampler ?? self.sessionSampler,
            trackBackgroundEvents: trackBackgroundEvents ?? self.trackBackgroundEvents,
            trackFrustrations: trackFrustrations ?? self.trackFrustrations,
            hasAppHangsEnabled: hasAppHangsEnabled ?? self.hasAppHangsEnabled,
            firstPartyHosts: firstPartyHosts ?? self.firstPartyHosts,
            eventBuilder: eventBuilder ?? self.eventBuilder,
            rumUUIDGenerator: rumUUIDGenerator ?? self.rumUUIDGenerator,
            backtraceReporter: backtraceReporter ?? self.backtraceReporter,
            ciTest: ciTest ?? self.ciTest,
            syntheticsTest: syntheticsTest ?? self.syntheticsTest,
            renderLoopObserver: renderLoopObserver ?? self.renderLoopObserver,
            viewHitchesMetricFactory: viewHitchesMetricFactory ?? self.viewHitchesMetricFactory,
            vitalsReaders: vitalsReaders ?? self.vitalsReaders,
            onSessionStart: onSessionStart ?? self.onSessionStart,
            viewCache: viewCache ?? self.viewCache,
            fatalErrorContext: fatalErrorContext ?? self.fatalErrorContext,
            sessionEndedMetric: sessionEndedMetric ?? self.sessionEndedMetric,
            viewEndedMetricFactory: viewEndedMetricFactory ?? self.viewEndedMetricFactory,
            watchdogTermination: watchdogTermination ?? self.watchdogTermination,
            networkSettledMetricFactory: networkSettledMetricFactory ?? self.networkSettledMetricFactory,
            interactionToNextViewMetricFactory: interactionToNextViewMetricFactory ?? self.interactionToNextViewMetricFactory
        )
    }
}

extension RUMApplicationScope {
    public static func mockAny() -> RUMApplicationScope {
        return RUMApplicationScope(dependencies: .mockAny())
    }
}

extension RUMSessionScope {
    public static func mockAny() -> RUMSessionScope {
        return mockWith()
    }

    // swiftlint:disable function_default_parameter_at_end
    public static func mockWith(
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

public func createMockViewInWindow() -> UIViewController {
    let viewController = UIViewController()
    mockWindow.rootViewController = viewController
    mockWindow.makeKeyAndVisible()
    return viewController
}

/// Creates an instance of `UIViewController` subclass with a given name.
public func createMockView(viewControllerClassName: String) -> UIViewController {
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
    public static func mockAny() -> RUMViewScope {
        return mockWith()
    }

    public static func randomTimings() -> [String: Int64] {
        var timings: [String: Int64] = [:]
        (0..<10).forEach { index in timings["timing\(index)"] = .mockRandom() }
        return timings
    }

    public static func mockWith(
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
    public static func mockWith(
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
        networkSettledMetric: TNSMetricTracking = TNSMetric(viewName: .mockAny(), viewStartDate: .mockAny(), resourcePredicate: TimeBasedTNSResourcePredicate()),
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
    public static func mockWith(
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

public class RUMContextProviderMock: RUMContextProvider {
    public init(context: RUMContext = .mockAny()) {
        self.context = context
    }

    public var context: RUMContext
}

// MARK: - Auto Instrumentation Mocks

public class RUMCommandSubscriberMock: RUMCommandSubscriber {
    public var onCommandReceived: ((RUMCommand) -> Void)?
    public var receivedCommands: [RUMCommand] = []
    public var lastReceivedCommand: RUMCommand? { receivedCommands.last }

    public init() {}
    public func process(command: RUMCommand) {
        receivedCommands.append(command)
        onCommandReceived?(command)
    }
}

public class UIKitRUMViewsPredicateMock: UIKitRUMViewsPredicate {
    public var resultByViewController: [UIViewController: RUMView] = [:]
    public var result: RUMView?

    public init(result: RUMView? = nil) {
        self.result = result
    }

    public func rumView(for viewController: UIViewController) -> RUMView? {
        return resultByViewController[viewController] ?? result
    }
}

public class UIKitRUMViewsHandlerMock: UIViewControllerHandler {
    public var onSubscribe: ((RUMCommandSubscriber) -> Void)?
    public var notifyViewDidAppear: ((UIViewController, Bool) -> Void)?
    public var notifyViewDidDisappear: ((UIViewController, Bool) -> Void)?

    public init() {}

    public func publish(to subscriber: RUMCommandSubscriber) {
        onSubscribe?(subscriber)
    }

    public func notify_viewDidAppear(viewController: UIViewController, animated: Bool) {
        notifyViewDidAppear?(viewController, animated)
    }

    public func notify_viewDidDisappear(viewController: UIViewController, animated: Bool) {
        notifyViewDidDisappear?(viewController, animated)
    }
}

#if os(tvOS)
public typealias UIKitRUMActionsPredicateMock = UIPressRUMActionsPredicateMock
#else
public typealias UIKitRUMActionsPredicateMock = UITouchRUMActionsPredicateMock
#endif

public class UITouchRUMActionsPredicateMock: UITouchRUMActionsPredicate {
    public var resultByView: [UIView: RUMAction] = [:]
    public var result: RUMAction?

    public init(result: RUMAction? = nil) {
        self.result = result
    }

    public func rumAction(targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

public class UIPressRUMActionsPredicateMock: UIPressRUMActionsPredicate {
    public var resultByView: [UIView: RUMAction] = [:]
    public var result: RUMAction?

    public init(result: RUMAction? = nil) {
        self.result = result
    }

    public func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        return resultByView[targetView] ?? result
    }
}

public class RUMActionsHandlerMock: RUMActionsHandling {
    public var onSubscribe: ((RUMCommandSubscriber) -> Void)?
    public var onSendEvent: ((UIApplication, UIEvent) -> Void)?
    public var onViewModifierTapped: ((String, [String: any Encodable]) -> Void)?

    public init() { }

    public func publish(to subscriber: RUMCommandSubscriber) {
        onSubscribe?(subscriber)
    }

    public func notify_sendEvent(application: UIApplication, event: UIEvent) {
        onSendEvent?(application, event)
    }

    public func notify_viewModifierTapped(actionName: String, actionAttributes: [String: any Encodable]) {
        onViewModifierTapped?(actionName, actionAttributes)
    }
}

public class SamplingBasedVitalReaderMock: SamplingBasedVitalReader {
    public var vitalData: Double?

    public init() {}
    public func readVitalData() -> Double? {
        return vitalData
    }
}

public class ContinuousVitalReaderMock: ContinuousVitalReader {
    public var vitalInfo = VitalInfo() {
        didSet {
            publishers.forEach {
                $0.publishAsync(vitalInfo)
            }
        }
    }
    public var publishers = [VitalPublisher]()

    public init() {}

    public func register(_ valuePublisher: VitalPublisher) {
        publishers.append(valuePublisher)
    }

    public func unregister(_ valuePublisher: VitalPublisher) {
        publishers.removeAll { existingPublisher in
            return existingPublisher === valuePublisher
        }
    }
}

extension TelemetryReceiver: AnyMockable {
    public static func mockAny() -> Self { .mockWith() }

    public static func mockWith(
        featureScope: FeatureScope = NOPFeatureScope(),
        dateProvider: DateProvider = SystemDateProvider(),
        sampler: Sampler = .mockKeepAll(),
        configurationExtraSampler: Sampler = .mockKeepAll()
    ) -> Self {
        .init(
            featureScope: featureScope,
            dateProvider: dateProvider,
            sampler: sampler,
            configurationExtraSampler: configurationExtraSampler
        )
    }
}

extension RUMApplicationStartCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMApplicationStartCommand { mockWith() }

    public static func mockRandom() -> RUMApplicationStartCommand {
        return .mockWith(
            time: .mockRandomInThePast(),
            attributes: mockRandomAttributes()
        )
    }

    public static func mockWith(
        time: Date = Date(),
        globalAttributes: [AttributeKey: AttributeValue] = [:],
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMApplicationStartCommand {
        return RUMApplicationStartCommand(
            time: time,
            globalAttributes: globalAttributes,
            attributes: attributes,
            canStartBackgroundView: false,
            isUserInteraction: false
        )
    }
}

// MARK: - Dependency on Session Replay

extension ValuePublisher: AnyMockable where Value: AnyMockable {
    public static func mockAny() -> Self {
        return .init(initialValue: .mockAny())
    }
}

extension ValuePublisher: RandomMockable where Value: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(initialValue: .mockRandom())
    }
}

extension ValuePublisher {
    /// Publishes `newValue` using `publishSync(:_)` or `publishAsync(:_)`.
    public func publishSyncOrAsync(_ newValue: Value) {
        if Bool.random() {
            publishSync(newValue)
        } else {
            publishAsync(newValue)
        }
    }
}

public class ValueObserverMock<Value>: ValueObserver {
    public typealias ObservedValue = Value

    private(set) var onValueChange: ((Value, Value) -> Void)?
    private(set) var lastChange: (oldValue: Value, newValue: Value)?

    public init(onValueChange: ((Value, Value) -> Void)? = nil) {
        self.onValueChange = onValueChange
    }

    public func onValueChanged(oldValue: Value, newValue: Value) {
        lastChange = (oldValue, newValue)
        onValueChange?(oldValue, newValue)
    }
}

// MARK: - Dependency on Session Replay

extension Dictionary where Key == String, Value == FeatureBaggage {
    public static func mockSessionReplayAttributes(hasReplay: Bool?, recordsCountByViewID: [String: Int64]? = nil) throws -> Self {
        return [
            SessionReplayDependency.hasReplay: .init(hasReplay),
            SessionReplayDependency.recordsCountByViewID: .init(recordsCountByViewID)
        ]
    }
}

// MARK: - App Hangs Monitoring

extension AppHang: AnyMockable, RandomMockable {
    public static func mockAny() -> AppHang {
        return .mockWith()
    }

    public static func mockRandom() -> AppHang {
        return AppHang(
            startDate: .mockRandom(),
            backtraceResult: .mockRandom()
        )
    }

    public static func mockWith(
        startDate: Date = .mockAny(),
        backtraceResult: BacktraceGenerationResult = .mockAny()
    ) -> AppHang {
        return AppHang(
            startDate: startDate,
            backtraceResult: backtraceResult
        )
    }
}

extension AppHang.BacktraceGenerationResult: AnyMockable, RandomMockable {
    public static func mockAny() -> AppHang.BacktraceGenerationResult {
        return .succeeded(.mockAny())
    }

    public static func mockRandom() -> AppHang.BacktraceGenerationResult {
        return [
            .succeeded(.mockRandom()),
            .failed,
            .notAvailable
        ].randomElement()!
    }
}

// MARK: - View Loading Metrics

public class TNSMetricMock: TNSMetricTracking {
    /// Tracks calls to `trackResourceStart(at:resourceID:)`.
    public var resourceStartDates: [RUMUUID: Date] = [:]
    /// Tracks calls to `trackResourceEnd(at:resourceID:resourceDuration:)`.
    public var resourceEndDates: [RUMUUID: (Date, TimeInterval?)] = [:]
    /// Tracks calls to `trackResourceDropped(resourceID:)`.
    public var resourcesDropped: Set<RUMUUID> = []
    /// Tracks if `trackViewWasStopped()` was called.
    public var viewWasStopped = false
    /// Mocked value returned by this metric.
    public var value: Result<TimeInterval, TNSNoValueReason>

    public init(value: Result<TimeInterval, TNSNoValueReason> = .failure(.unknown)) {
        self.value = value
    }

    public func trackResourceStart(at startDate: Date, resourceID: RUMUUID, resourceURL: String) {
        resourceStartDates[resourceID] = startDate
    }

    public func trackResourceEnd(at endDate: Date, resourceID: RUMUUID, resourceDuration: TimeInterval?) {
        resourceEndDates[resourceID] = (endDate, resourceDuration)
    }

    public func trackResourceDropped(resourceID: RUMUUID) {
        resourcesDropped.insert(resourceID)
    }

    public func trackViewWasStopped() {
        viewWasStopped = true
    }

    public func value(with appStateHistory: AppStateHistory) -> Result<TimeInterval, TNSNoValueReason> {
        return value
    }
}

public class INVMetricMock: INVMetricTracking {
    /// Tracks calls to `trackAction(startTime:endTime:name:type:in:)`.
    public var trackedActions: [(startTime: Date, endTime: Date, actionName: String, actionType: RUMActionType, viewID: RUMUUID)] = []
    /// Tracks calls to `trackViewStart(at:name:viewID:)`.
    public var trackedViewStarts: [(viewStart: Date, viewName: String, viewID: RUMUUID)] = []
    /// Tracks calls to `trackViewComplete(viewID:)`.
    public var trackedViewCompletes: Set<RUMUUID> = []
    /// Mocked value returned by this metric.
    public var mockedValue: Result<TimeInterval, INVNoValueReason>

    public init(mockedValue: Result<TimeInterval, INVNoValueReason> = .failure(.noTrackedActions)) {
        self.mockedValue = mockedValue
    }

    public func trackAction(startTime: Date, endTime: Date, name: String, type: RUMActionType, in viewID: RUMUUID) {
        trackedActions.append((startTime: startTime, endTime: endTime, actionName: name, actionType: type, viewID: viewID))
    }

    public func trackViewStart(at viewStart: Date, name: String, viewID: RUMUUID) {
        trackedViewStarts.append((viewStart: viewStart, viewName: name, viewID: viewID))
    }

    public func trackViewComplete(viewID: RUMUUID) {
        trackedViewCompletes.insert(viewID)
    }

    public func value(for viewID: RUMUUID) -> Result<TimeInterval, INVNoValueReason> {
        return mockedValue
    }
}

extension RUMAddCurrentViewAppHangCommand: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMAddCurrentViewAppHangCommand {
        return .mockWith()
    }

    public static func mockRandom() -> RUMAddCurrentViewAppHangCommand {
        return RUMAddCurrentViewAppHangCommand(
            time: .mockRandom(),
            attributes: mockRandomAttributes(),
            message: .mockRandom(),
            type: .mockRandom(),
            stack: .mockRandom(),
            threads: .mockRandom(),
            binaryImages: .mockRandom(),
            isStackTraceTruncated: .mockRandom(),
            hangDuration: .mockRandom()
        )
    }

    public static func mockWith(
        time: Date = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        message: String = .mockAny(),
        type: String? = .mockAny(),
        stack: String? = .mockAny(),
        threads: [DDThread]? = .mockAny(),
        binaryImages: [BinaryImage]? = .mockAny(),
        isStackTraceTruncated: Bool? = .mockAny(),
        hangDuration: TimeInterval = .mockAny()
    ) -> RUMAddCurrentViewAppHangCommand {
        return RUMAddCurrentViewAppHangCommand(
            time: time,
            attributes: attributes,
            message: message,
            type: type,
            stack: stack,
            threads: threads,
            binaryImages: binaryImages,
            isStackTraceTruncated: isStackTraceTruncated,
            hangDuration: hangDuration
        )
    }
}

extension RUMCoreContext: RandomMockable {
    public static func mockRandom() -> RUMCoreContext {
        RUMCoreContext(
            applicationID: .mockRandom(),
            sessionID: .mockRandom(),
            viewID: .mockRandom(),
            userActionID: .mockRandom(),
            viewServerTimeOffset: .mockRandom()
        )
    }
}

extension RUMResourceScope {
    public static func mockWith(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String = .mockAny(),
        startTime: Date = .mockAny(),
        serverTimeOffset: TimeInterval = .zero,
        url: String = .mockAny(),
        httpMethod: RUMMethod = .mockAny(),
        isFirstPartyResource: Bool? = nil,
        resourceKindBasedOnRequest: RUMResourceType? = nil,
        spanContext: RUMSpanContext? = .mockAny(),
        networkSettledMetric: TNSMetricTracking = TNSMetric(viewName: .mockAny(), viewStartDate: .mockAny(), resourcePredicate: TimeBasedTNSResourcePredicate()),
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

// MARK: - Auto Instrumentation Mocks

public class UIKitPredicateWithTrackingMock: UIKitRUMViewsPredicate {
    public var numberOfCalls: Int

    public init(numberOfCalls: Int = 0) {
        self.numberOfCalls = numberOfCalls
    }

    public func rumView(for viewController: UIViewController) -> RUMView? {
        numberOfCalls += 1
        return .init(name: .mockRandom())
    }
}

public class UIKitPredicateWithModalMock: UIKitRUMViewsPredicate {
    let untrackedModal: UIViewController

    public init(untrackedModal: UIViewController) {
        self.untrackedModal = untrackedModal
    }

    public func rumView(for viewController: UIViewController) -> RUMView? {
        let isUntrackedModal = viewController == untrackedModal
        return .init(name: .mockRandom(), isUntrackedModal: isUntrackedModal)
    }
}

public class SwiftUIRUMViewsPredicateMock: SwiftUIRUMViewsPredicate {
    public var resultByViewName: [String: RUMView] = [:]
    public var result: RUMView?

    public init(result: RUMView? = nil) {
        self.result = result
    }

    public func rumView(for extractedViewName: String) -> RUMView? {
        return resultByViewName[extractedViewName] ?? result
    }
}

public class SwiftUIViewNameExtractorMock: SwiftUIViewNameExtractor {
    public var resultByViewController: [UIViewController: String] = [:]
    public var defaultResult: String?

    public init(defaultResult: String? = nil) {
        self.defaultResult = defaultResult
    }

    public func extractName(from viewController: UIViewController) -> String? {
        return resultByViewController[viewController] ?? defaultResult
    }
}
