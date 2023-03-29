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
        let uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?
        let uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate?
        let longTaskThreshold: TimeInterval?

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

    let customIntakeURL: URL?
    let applicationID: String
    let sessionSampler: Sampler
    let telemetrySampler: Sampler
    let configurationTelemetrySampler: Sampler?
    let uuidGenerator: RUMUUIDGenerator
    let viewEventMapper: RUMViewEventMapper?
    let resourceEventMapper: RUMResourceEventMapper?
    let actionEventMapper: RUMActionEventMapper?
    let errorEventMapper: RUMErrorEventMapper?
    let longTaskEventMapper: RUMLongTaskEventMapper?
    /// RUM auto instrumentation configuration, `nil` if not enabled.
    let instrumentation: Instrumentation
    let backgroundEventTrackingEnabled: Bool
    let frustrationTrackingEnabled: Bool
    let onSessionStart: RUMSessionListener?
    let firstPartyHosts: FirstPartyHosts
    let tracingSampler: Sampler?
    /// An optional RUM Resource attributes provider.
    let rumAttributesProvider: URLSessionRUMAttributesProvider?
    let vitalsFrequency: TimeInterval?
    let dateProvider: DateProvider

    public init(
        applicationID: String,
        sessionSampler: Sampler = Sampler(samplingRate: 100),
        telemetrySampler: Sampler = Sampler(samplingRate: 20),
        configurationTelemetrySampler: Sampler? = nil,
        viewEventMapper: RUMViewEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil,
        instrumentation: Instrumentation = .init(),
        backgroundEventTrackingEnabled: Bool = false,
        frustrationTrackingEnabled: Bool = true,
        onSessionStart: RUMSessionListener? = nil,
        firstPartyHosts: FirstPartyHosts = .init(),
        tracingSampler: Sampler? = nil,
        rumAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        vitalsFrequency: TimeInterval? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        customIntakeURL: URL? = nil
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
        self.rumAttributesProvider = rumAttributesProvider
        self.vitalsFrequency = vitalsFrequency
        self.dateProvider = dateProvider
    }

    init(
        applicationID: String,
        uuidGenerator: RUMUUIDGenerator,
        sessionSampler: Sampler = Sampler(samplingRate: 100),
        telemetrySampler: Sampler = Sampler(samplingRate: 20),
        configurationTelemetrySampler: Sampler? = nil,
        viewEventMapper: RUMViewEventMapper? = nil,
        resourceEventMapper: RUMResourceEventMapper? = nil,
        actionEventMapper: RUMActionEventMapper? = nil,
        errorEventMapper: RUMErrorEventMapper? = nil,
        longTaskEventMapper: RUMLongTaskEventMapper? = nil,
        instrumentation: Instrumentation = .init(),
        backgroundEventTrackingEnabled: Bool = false,
        frustrationTrackingEnabled: Bool = true,
        onSessionStart: RUMSessionListener? = nil,
        firstPartyHosts: FirstPartyHosts = .init(),
        tracingSampler: Sampler? = nil,
        rumAttributesProvider: URLSessionRUMAttributesProvider? = nil,
        vitalsFrequency: TimeInterval? = nil,
        dateProvider: DateProvider = SystemDateProvider(),
        customIntakeURL: URL? = nil
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
        self.rumAttributesProvider = rumAttributesProvider
        self.vitalsFrequency = vitalsFrequency
        self.dateProvider = dateProvider
    }
}
