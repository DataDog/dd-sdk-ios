/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

// Export `DDURLSessionDelegate` elements to be available with `import DatadogRUM`:
// swiftlint:disable duplicate_imports
@_exported import class DatadogInternal.DatadogURLSessionDelegate
@_exported import typealias DatadogInternal.DDURLSessionDelegate
@_exported import protocol DatadogInternal.__URLSessionDelegateProviding
@_exported import enum DatadogInternal.URLSessionInstrumentation
// swiftlint:enable duplicate_imports

extension RUM {
    /// RUM view event mapper.
    /// - See: `RUM.Configuration.viewEventMapper`.
    public typealias ViewEventMapper = (RUMViewEvent) -> RUMViewEvent

    /// RUM resource event mapper.
    /// - See: `RUM.Configuration.resourceEventMapper`.
    public typealias ResourceEventMapper = (RUMResourceEvent) -> RUMResourceEvent?

    /// RUM error event mapper.
    /// - See: `RUM.Configuration.errorEventMapper`.
    public typealias ErrorEventMapper = (RUMErrorEvent) -> RUMErrorEvent?

    /// RUM action event mapper.
    /// - See: `RUM.Configuration.actionEventMapper`.
    public typealias ActionEventMapper = (RUMActionEvent) -> RUMActionEvent?

    /// RUM long task event mapper.
    /// - See: `RUM.Configuration.longTaskEventMapper`.
    public typealias LongTaskEventMapper = (RUMLongTaskEvent) -> RUMLongTaskEvent?

    /// RUM session listener.
    /// - See: `RUM.Configuration.onSessionStart`.
    public typealias SessionListener = (String, Bool) -> Void

    /// RUM resource attributes provider.
    /// - See: `RUM.Configuration.URLSessionTracking.resourceAttributesProvider`.
    public typealias ResourceAttributesProvider = (URLRequest, URLResponse?, Data?, Error?) -> [AttributeKey: AttributeValue]?

    /// RUM feature configuration.
    public struct Configuration {
        /// An unique identifier of the RUM application in Datadog.
        public let applicationID: String

        /// The sampling rate for RUM sessions.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no sessions will be sent
        /// and 100 means all will be uploaded.
        ///
        /// Default: `100.0`.
        public var sessionSampleRate: Float

        /// The predicate for automatically tracking `UIViewControllers` as RUM views.
        ///
        /// RUM will query this predicate for each `UIViewController` presented in the app. The predicate implementation
        /// should return RUM view parameters if the given controller should start a view, or `nil` to ignore it.
        ///
        /// You can use `DefaultUIKitRUMViewsPredicate` or create your own predicate by implementing `UIKitRUMViewsPredicate`.
        ///
        /// Note: Automatic RUM views tracking involves swizzling the `UIViewController` lifecycle methods.
        ///
        /// Default: `nil` - which means automatic RUM view tracking is not enabled by default.
        public var uiKitViewsPredicate: UIKitRUMViewsPredicate?

        /// The predicate for automatically tracking `UITouch` events as RUM actions.
        ///
        /// RUM will query this predicate for each `UIView` that the user interacts with. The predicate implementation
        /// should return RUM action parameters if the given interaction should be accepted, or `nil` to ignore it.
        /// Touch events on the keyboard are ignored for privacy reasons.
        ///
        /// You can use `DefaultUIKitRUMActionsPredicate` or create your own predicate by
        /// implementing `UIKitRUMActionsPredicate`.
        ///
        /// Note: Automatic RUM action tracking involves swizzling the `UIApplication.sendEvent(_:)` method.
        ///
        /// Default: `nil` - which means automatic RUM action tracking is not enabled by default.
        public var uiKitActionsPredicate: UIKitRUMActionsPredicate?

        /// The configuration for automatic RUM resources tracking.
        ///
        /// RUM resources tracking requires enabling `URLSessionInstrumentation`. See
        /// ``URLSessionInstrumentation.enable(with:)`.
        ///
        /// Note: Automatic RUM resources tracking involves swizzling the `URLSession`, `URLSessionTask` and
        /// `URLSessionDataDelegate` methods.
        ///
        /// Default: `nil` - which means automatic RUM resource tracking is not enabled by default.
        public var urlSessionTracking: URLSessionTracking?

        /// Determines whether automatic tracking of user frustrations should be enabled.
        ///
        /// RUM detects "error taps"  when an error follows a RUM tap action.
        ///
        /// Default: `true`.
        public var trackFrustrations: Bool

        /// Determines whether RUM events should be tracked when no view is active (including when the app is in the background).
        ///
        /// If enabled, RUM will attach events to an automatically created "background" view.
        ///
        /// Note: Enabling this option may increase the number of sessions tracked and result in higher billing.
        ///
        /// Default: `false`.
        public var trackBackgroundEvents: Bool

        /// Enables RUM long tasks tracking with the given threshold (in seconds).
        ///
        /// Any operation on the main thread that exceeds this threshold will be reported as a RUM long task.
        /// To disable RUM long tasks tracking, set `nil` or `0`.
        ///
        /// Default: `0.1`.
        public var longTaskThreshold: TimeInterval?

        /// Sets the preferred frequency for collecting RUM vitals.
        ///
        /// To disable RUM vitals monitoring, set `nil`.
        ///
        /// Default: `.average`.
        public var vitalsUpdateFrequency: VitalsFrequency?

        /// Custom mapper for RUM view events.
        ///
        /// It can be used to modify view events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `RUMViewEvent`, modify it, and return it. Keep the implementation fast
        /// and do not make any assumptions on the thread used to run it.
        ///
        /// Note: This mapper ensures that all views are sent by preventing the return of `nil`. To drop certain automatically
        /// collected RUM views, adjust the implementation of the view predicate (see the `uiKitViewsPredicate` option).
        ///
        /// Default: `nil`.
        public var viewEventMapper: RUM.ViewEventMapper?

        /// Custom mapper for RUM resource events.
        ///
        /// It can be used to modify resource events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `RUMResourceEvent`, modify it, and return it. Returning `nil` will drop the event.
        /// Keep the implementation fast and do not make any assumptions on the thread used to run it.
        ///
        /// Default: `nil`.
        public var resourceEventMapper: RUM.ResourceEventMapper?

        /// Custom mapper for RUM action events.
        ///
        /// It can be used to modify action events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `RUMActionEvent`, modify it, and return it. Returning `nil` will drop the event.
        /// Keep the implementation fast and do not make any assumptions on the thread used to run it.
        ///
        /// Default: `nil`.
        public var actionEventMapper: RUM.ActionEventMapper?

        /// Custom mapper for RUM error events.
        ///
        /// It can be used to modify error events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `RUMErrorEvent`, modify it, and return it. Returning `nil` will drop the event.
        /// Keep the implementation fast and do not make any assumptions on the thread used to run it.
        ///
        /// Default: `nil`.
        public var errorEventMapper: RUM.ErrorEventMapper?

        /// Custom mapper for RUM long task events.
        ///
        /// It can be used to modify long task events before they are sent. The implementation of the mapper should
        /// obtain a mutable copy of `RUMLongTaskEvent`, modify it, and return it. Returning `nil` will drop the event.
        /// Keep the implementation fast and do not make any assumptions on the thread used to run it.
        ///
        /// Default: `nil`.
        public var longTaskEventMapper: RUM.LongTaskEventMapper?

        /// RUM session start callback.
        ///
        /// It takes 2 arguments:
        /// - Newly started session ID.
        /// - Flag indicating whether or not the session was discarded due to the sampling rate.
        /// Keep the implementation fast and do not make any assumptions on the thread that runs this callback.
        ///
        /// Default: `nil`.
        public var onSessionStart: RUM.SessionListener?

        /// Custom server url for sending RUM data.
        ///
        /// Default: `nil`.
        public var customEndpoint: URL?

        /// The sampling rate for SDK internal telemetry utilized by Datadog.
        /// This telemetry is used to monitor the internal workings of the entire Datadog iOS SDK.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no telemetry will be sent,
        /// and 100 means all telemetry will be uploaded. The default value is 20.0.
        public var telemetrySampleRate: Float

        // MARK: - Nested Types

        /// Configuration of automatic RUM resources tracking.
        public struct URLSessionTracking {
            /// Determines distributed tracing configuration for particular first-party hosts.
            ///
            /// Each request is classified as first-party or third-party based on the first-party hosts configured, i.e.:
            /// * If "example.com" is defined as a first-party host:
            ///     - First-party URL examples: https://example.com/ and https://api.example.com/v2/users
            ///     - Third-party URL example: https://foo.com/
            /// * If "api.example.com" is defined as a first-party host:
            ///     - First-party URL examples: https://api.example.com/ and https://api.example.com/v2/users
            ///     - Third-party URL examples: https://example.com/ and https://foo.com/
            ///
            /// RUM will create a trace for each first-party resource by injecting HTTP trace headers and creating an APM span.
            /// If your backend is also instrumented with Datadog, you will see the full trace (app → backend).
            ///
            /// Default: `nil` - which means distributed tracing is not enabled by default.
            public var firstPartyHostsTracing: FirstPartyHostsTracing?

            /// Custom attributes provider for intercepted RUM resources.
            ///
            /// This closure gets called for each network request intercepted by RUM. Use it to return additional
            /// attributes for RUM resource based on the provided request, response, data, and error.
            /// Keep the implementation fast and do not make any assumptions on the thread used to run it.
            ///
            /// Default: `nil`.
            public var resourceAttributesProvider: RUM.ResourceAttributesProvider?

            /// Private init to avoid `invalid redeclaration of synthesized memberwise init(...:)` in extension.
            private init() {}
        }

        /// Frequency for collecting RUM vitals.
        public enum VitalsFrequency: String {
            /// Every `100ms`.
            case frequent
            /// Every `500ms`.
            case average
            /// Every `1000ms`.
            case rare
        }

        // MARK: - Internal

        /// An extra sampling rate for configuration telemetry events.
        ///
        /// It is applied on top of the value configured in public `telemetrySampleRate`.
        /// It can be overwritten by `InternalConfiguration`.
        internal var configurationTelemetrySampleRate: Float = 20.0

        /// An extra sampling rate for metric events.
        ///
        /// It is applied on top of the value configured in public `telemetrySampleRate`.
        internal var metricsTelemetrySampleRate: Float = 15

        internal var uuidGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator()

        internal var traceIDGenerator: TraceIDGenerator = DefaultTraceIDGenerator()

        internal var dateProvider: DateProvider = SystemDateProvider()
        /// The main queue, subject to App Hangs monitoring.
        internal var mainQueue: DispatchQueue = .main
        /// The minimum main queue hang to be tracked as App Hang.
        internal var defaultAppHangThreshold: TimeInterval = 2

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)
        internal var debugViews: Bool = ProcessInfo.processInfo.arguments.contains("DD_DEBUG_RUM")
        internal var ciTestExecutionID: String? = ProcessInfo.processInfo.environment["CI_VISIBILITY_TEST_EXECUTION_ID"]
        internal var syntheticsTestId: String? = ProcessInfo.processInfo.environment["_dd.synthetics.test_id"]
        internal var syntheticsResultId: String? = ProcessInfo.processInfo.environment["_dd.synthetics.result_id"]
    }
}

extension RUM.Configuration.URLSessionTracking {
    /// Defines configuration for first-party hosts in distributed tracing.
    public enum FirstPartyHostsTracing {
        /// Trace the specified hosts using Datadog and W3C `tracecontext` tracing headers.
        ///
        /// - Parameters:
        ///   - hosts: The set of hosts to inject tracing headers. Note: Hosts must not include the "http(s)://" prefix.
        ///   - sampleRate: The sampling rate for tracing. Must be a value between `0.0` and `100.0`. Default: `20`.
        case trace(hosts: Set<String>, sampleRate: Float = 20)

        /// Trace given hosts with using custom tracing headers.
        ///
        /// - `hostsWithHeaders` - Dictionary of hosts and tracing header types to use. Note: Hosts must not include "http(s)://" prefix.
        /// - `sampleRate` - The sampling rate for tracing. Must be a value between `0.0` and `100.0`. Default: `20`.
        case traceWithHeaders(hostsWithHeaders: [String: Set<TracingHeaderType>], sampleRate: Float = 20)
    }

    /// Configuration for automatic RUM resources tracking.
    /// - Parameters:
    ///   - firstPartyHostsTracing: Distributed tracing configuration for particular first-party hosts.
    ///   - resourceAttributesProvider: Custom attributes provider for intercepted RUM resources.
    public init(
        firstPartyHostsTracing: RUM.Configuration.URLSessionTracking.FirstPartyHostsTracing? = nil,
        resourceAttributesProvider: RUM.ResourceAttributesProvider? = nil
    ) {
        self.firstPartyHostsTracing = firstPartyHostsTracing
        self.resourceAttributesProvider = resourceAttributesProvider
    }
}

extension RUM.Configuration {
    /// Creates RUM configuration.
    /// - Parameters:
    ///   - applicationID: The RUM application identifier.
    ///   - sessionSampleRate: The sampling rate for RUM sessions. Must be a value between `0` and `100`. Default: `100`.
    ///   - uiKitViewsPredicate: The predicate for automatically tracking `UIViewControllers` as RUM views. Default: `nil`.
    ///   - uiKitActionsPredicate: The predicate for automatically tracking `UITouch` events as RUM actions. Default: `nil`.
    ///   - urlSessionTracking: The configuration for automatic RUM resources tracking. Default: `nil`.
    ///   - trackFrustrations: Determines whether automatic tracking of user frustrations should be enabled. Default: `true`.
    ///   - trackBackgroundEvents: Determines whether RUM events should be tracked when no view is active. Default: `false`.
    ///   - longTaskThreshold: The threshold for RUM long tasks tracking (in seconds). Default: `0.1`.
    ///   - vitalsUpdateFrequency: The preferred frequency for collecting RUM vitals. Default: `.average`.
    ///   - viewEventMapper: Custom mapper for RUM view events. Default: `nil`.
    ///   - resourceEventMapper: Custom mapper for RUM resource events. Default: `nil`.
    ///   - actionEventMapper: Custom mapper for RUM action events. Default: `nil`.
    ///   - errorEventMapper: Custom mapper for RUM error events. Default: `nil`.
    ///   - longTaskEventMapper: Custom mapper for RUM long task events. Default: `nil`.
    ///   - onSessionStart: RUM session start callback. Default: `nil`.
    ///   - customEndpoint: Custom server url for sending RUM data. Default: `nil`.
    ///   - telemetrySampleRate: The sampling rate for SDK internal telemetry utilized by Datadog. Must be a value between `0` and `100`. Default: `20`.
    public init(
        applicationID: String,
        sessionSampleRate: Float = 100,
        uiKitViewsPredicate: UIKitRUMViewsPredicate? = nil,
        uiKitActionsPredicate: UIKitRUMActionsPredicate? = nil,
        urlSessionTracking: URLSessionTracking? = nil,
        trackFrustrations: Bool = true,
        trackBackgroundEvents: Bool = false,
        longTaskThreshold: TimeInterval? = 0.1,
        vitalsUpdateFrequency: VitalsFrequency? = .average,
        viewEventMapper: RUM.ViewEventMapper? = nil,
        resourceEventMapper: RUM.ResourceEventMapper? = nil,
        actionEventMapper: RUM.ActionEventMapper? = nil,
        errorEventMapper: RUM.ErrorEventMapper? = nil,
        longTaskEventMapper: RUM.LongTaskEventMapper? = nil,
        onSessionStart: RUM.SessionListener? = nil,
        customEndpoint: URL? = nil,
        telemetrySampleRate: Float = 20
    ) {
        self.applicationID = applicationID
        self.sessionSampleRate = sessionSampleRate
        self.uiKitViewsPredicate = uiKitViewsPredicate
        self.uiKitActionsPredicate = uiKitActionsPredicate
        self.urlSessionTracking = urlSessionTracking
        self.trackFrustrations = trackFrustrations
        self.trackBackgroundEvents = trackBackgroundEvents
        self.longTaskThreshold = longTaskThreshold
        self.vitalsUpdateFrequency = vitalsUpdateFrequency
        self.viewEventMapper = viewEventMapper
        self.resourceEventMapper = resourceEventMapper
        self.actionEventMapper = actionEventMapper
        self.errorEventMapper = errorEventMapper
        self.longTaskEventMapper = longTaskEventMapper
        self.onSessionStart = onSessionStart
        self.customEndpoint = customEndpoint
        self.telemetrySampleRate = telemetrySampleRate
    }
}

extension RUM.Configuration: InternalExtended {}
extension InternalExtension where ExtendedType == RUM.Configuration {
    /// The sampling rate for configuration telemetry events. When set, it overwrites the value
    /// of `configurationTelemetrySampleRate` in `RUM.Configuration`.
    ///
    /// It is mostly used to enable or disable telemetry events when running test scenarios.
    /// Expects value between `0.0` and `100.0`.
    public var configurationTelemetrySampleRate: Float {
        get { type.configurationTelemetrySampleRate }
        set { type.configurationTelemetrySampleRate = newValue }
    }
}
