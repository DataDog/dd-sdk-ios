/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

public typealias RUMSessionListener = (String, Bool) -> Void

public typealias RUMViewEventMapper = (RUMViewEvent) -> RUMViewEvent
public typealias RUMErrorEventMapper = (RUMErrorEvent) -> RUMErrorEvent?
public typealias RUMResourceEventMapper = (RUMResourceEvent) -> RUMResourceEvent?
public typealias RUMActionEventMapper = (RUMActionEvent) -> RUMActionEvent?
public typealias RUMLongTaskEventMapper = (RUMLongTaskEvent) -> RUMLongTaskEvent?

public typealias URLSessionRUMAttributesProvider = (URLRequest, URLResponse?, Data?, Error?) -> [AttributeKey: AttributeValue]?

public struct RUMConfiguration {
    public struct Instrumentation {
        public let uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?
        public let uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate?
        public let longTaskThreshold: TimeInterval?

        public init(
            uiKitRUMViewsPredicate: UIKitRUMViewsPredicate? = nil,
            uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate? = nil,
            longTaskThreshold: TimeInterval? = nil
        ) {
            self.uiKitRUMViewsPredicate = uiKitRUMViewsPredicate
            self.uiKitRUMUserActionsPredicate = uiKitRUMUserActionsPredicate
            self.longTaskThreshold = longTaskThreshold
        }
    }

    /* internal */ public var customIntakeURL: URL?
    /* internal */ public let applicationID: String
    /* internal */ public var sessionSampler: Sampler
    /* internal */ public var telemetrySampler: Sampler
    /* internal */ public var configurationTelemetrySampler: Sampler
    /* internal */ public var viewEventMapper: RUMViewEventMapper?
    /* internal */ public var resourceEventMapper: RUMResourceEventMapper?
    /* internal */ public var actionEventMapper: RUMActionEventMapper?
    /* internal */ public var errorEventMapper: RUMErrorEventMapper?
    /* internal */ public var longTaskEventMapper: RUMLongTaskEventMapper?
    /// RUM auto instrumentation configuration, `nil` if not enabled.
    /* internal */ public var instrumentation: Instrumentation
    /* internal */ public var backgroundEventTrackingEnabled: Bool
    /* internal */ public var frustrationTrackingEnabled: Bool
    /* internal */ public var onSessionStart: RUMSessionListener?
    /* internal */ public var firstPartyHosts: FirstPartyHosts?
    /* internal */ public var tracingSampler: Sampler
    /* internal */ public var traceIDGenerator: TraceIDGenerator
    /// An optional RUM Resource attributes provider.
    /* internal */ public var rumAttributesProvider: URLSessionRUMAttributesProvider?
    /* internal */ public var vitalsFrequency: TimeInterval?
    /* internal */ public var dateProvider: DateProvider
    /* internal */ public var testExecutionId: String?
    /* internal */ public var processInfo: ProcessInfo

    let uuidGenerator: RUMUUIDGenerator

    public init(
        applicationID: String,
        sessionSampler: Sampler = Sampler(samplingRate: 100),
        telemetrySampler: Sampler = Sampler(samplingRate: 20),
        configurationTelemetrySampler: Sampler = Sampler(samplingRate: 20),
        viewEventMapper: RUMViewEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil,
        instrumentation: Instrumentation = .init(),
        backgroundEventTrackingEnabled: Bool = false,
        frustrationTrackingEnabled: Bool = true,
        onSessionStart: RUMSessionListener? = nil,
        firstPartyHosts: FirstPartyHosts? = nil,
        tracingSampler: Sampler = Sampler(samplingRate: 20),
        traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        rumAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        vitalsFrequency: TimeInterval? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        customIntakeURL: URL? = nil,
        testExecutionId: String? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.customIntakeURL = customIntakeURL
        self.applicationID = applicationID
        self.sessionSampler = sessionSampler
        self.telemetrySampler = telemetrySampler
        self.configurationTelemetrySampler = configurationTelemetrySampler
        self.uuidGenerator = DefaultRUMUUIDGenerator()
        self.viewEventMapper = viewEventMapper
        self.resourceEventMapper = resourceEventMapper
        self.actionEventMapper = actionEventMapper
        self.errorEventMapper = errorEventMapper
        self.longTaskEventMapper = longTaskEventMapper
        self.instrumentation = instrumentation
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
        self.frustrationTrackingEnabled = frustrationTrackingEnabled
        self.onSessionStart = onSessionStart
        self.firstPartyHosts = firstPartyHosts
        self.tracingSampler = tracingSampler
        self.traceIDGenerator = traceIDGenerator
        self.rumAttributesProvider = rumAttributesProvider
        self.vitalsFrequency = vitalsFrequency
        self.dateProvider = dateProvider
        self.testExecutionId = testExecutionId
        self.processInfo = processInfo
    }

    init(
        applicationID: String,
        uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator(),
        sessionSampler: Sampler = Sampler(samplingRate: 100),
        telemetrySampler: Sampler = Sampler(samplingRate: 20),
        configurationTelemetrySampler: Sampler = Sampler(samplingRate: 20),
        viewEventMapper: RUMViewEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil,
        instrumentation: Instrumentation = .init(),
        backgroundEventTrackingEnabled: Bool = false,
        frustrationTrackingEnabled: Bool = true,
        onSessionStart: RUMSessionListener? = nil,
        firstPartyHosts: FirstPartyHosts? = nil,
        tracingSampler: Sampler = Sampler(samplingRate: 20),
        traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator(),
        rumAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        vitalsFrequency: TimeInterval? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        customIntakeURL: URL? = nil,
        testExecutionId: String? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.customIntakeURL = customIntakeURL
        self.applicationID = applicationID
        self.sessionSampler = sessionSampler
        self.telemetrySampler = telemetrySampler
        self.configurationTelemetrySampler = configurationTelemetrySampler
        self.uuidGenerator = uuidGenerator
        self.viewEventMapper = viewEventMapper
        self.resourceEventMapper = resourceEventMapper
        self.actionEventMapper = actionEventMapper
        self.errorEventMapper = errorEventMapper
        self.longTaskEventMapper = longTaskEventMapper
        self.instrumentation = instrumentation
        self.backgroundEventTrackingEnabled = backgroundEventTrackingEnabled
        self.frustrationTrackingEnabled = frustrationTrackingEnabled
        self.onSessionStart = onSessionStart
        self.firstPartyHosts = firstPartyHosts
        self.tracingSampler = tracingSampler
        self.traceIDGenerator = traceIDGenerator
        self.rumAttributesProvider = rumAttributesProvider
        self.vitalsFrequency = vitalsFrequency
        self.dateProvider = dateProvider
        self.testExecutionId = testExecutionId
        self.processInfo = processInfo
    }
}
