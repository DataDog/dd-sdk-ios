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

    /* internal */ public let customIntakeURL: URL?
    /* internal */ public let applicationID: String
    /* internal */ public let sessionSampler: Sampler
    /* internal */ public let telemetrySampler: Sampler
    /* internal */ public let configurationTelemetrySampler: Sampler
    /* internal */ public let viewEventMapper: RUMViewEventMapper?
    /* internal */ public let resourceEventMapper: RUMResourceEventMapper?
    /* internal */ public let actionEventMapper: RUMActionEventMapper?
    /* internal */ public let errorEventMapper: RUMErrorEventMapper?
    /* internal */ public let longTaskEventMapper: RUMLongTaskEventMapper?
    /// RUM auto instrumentation configuration, `nil` if not enabled.
    /* internal */ public let instrumentation: Instrumentation
    /* internal */ public let backgroundEventTrackingEnabled: Bool
    /* internal */ public let frustrationTrackingEnabled: Bool
    /* internal */ public let onSessionStart: RUMSessionListener?
    /* internal */ public let firstPartyHosts: FirstPartyHosts?
    /* internal */ public let tracingSampler: Sampler
    /* internal */ public let traceIDGenerator: TraceIDGenerator
    /// An optional RUM Resource attributes provider.
    /* internal */ public let rumAttributesProvider: URLSessionRUMAttributesProvider?
    /* internal */ public let vitalsFrequency: TimeInterval?
    /* internal */ public let dateProvider: DateProvider
    /* internal */ public let testExecutionId: String?

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
        testExecutionId: String? = nil
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
        testExecutionId: String? = nil
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
    }
}
