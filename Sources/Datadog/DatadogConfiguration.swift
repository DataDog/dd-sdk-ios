/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension Datadog {
    internal struct Constants {
        /// Value for `ddsource` send by different features.
        static let ddsource = "ios"
    }

    /// Datadog SDK configuration.
    public struct Configuration {
        /// Defines the Datadog SDK policy when batching data together before uploading it to Datadog servers.
        /// Smaller batches mean smaller but more network requests, whereas larger batches mean fewer but larger network requests.
        public enum BatchSize {
            /// Prefer small sized data batches.
            case small
            /// Prefer medium sized data batches.
            case medium
            /// Prefer large sized data batches.
            case large
        }

        /// Defines the frequency at which Datadog SDK will try to upload data batches.
        public enum UploadFrequency {
            /// Try to upload batched data frequently.
            case frequent
            /// Try to upload batched data with a medium frequency.
            case average
            /// Try to upload batched data rarely.
            case rare
        }

        public enum DatadogEndpoint {
            /// US based servers.
            /// Sends data to [app.datadoghq.com](https://app.datadoghq.com/).
            case us1
            /// US based servers.
            /// Sends data to [app.datadoghq.com](https://us3.datadoghq.com/).
            case us3
            /// US based servers.
            /// Sends data to [app.datadoghq.com](https://us5.datadoghq.com/).
            case us5
            /// Europe based servers.
            /// Sends data to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu1
            /// US based servers, FedRAMP compatible.
            /// Sends data to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case us1_fed
            /// US based servers.
            /// Sends data to [app.datadoghq.com](https://app.datadoghq.com/).
            @available(*, deprecated, message: "Renamed to us1")
            public static let us: DatadogEndpoint = .us1
            /// Europe based servers.
            /// Sends data to [app.datadoghq.eu](https://app.datadoghq.eu/).
            @available(*, deprecated, message: "Renamed to eu1")
            public static let eu: DatadogEndpoint = .eu1
            /// Gov servers.
            /// Sends data to [app.ddog-gov.com](https://app.ddog-gov.com/).
            @available(*, deprecated, message: "Renamed to us1_fed")
            public static let gov: DatadogEndpoint = .us1_fed

            internal var logsEndpoint: LogsEndpoint {
                switch self {
                case .us1: return .us1
                case .us3: return .us3
                case .us5: return .us5
                case .eu1: return .eu1
                case .us1_fed: return .us1_fed
                }
            }

            internal var tracesEndpoint: TracesEndpoint {
                switch self {
                case .us1: return .us1
                case .us3: return .us3
                case .us5: return .us5
                case .eu1: return .eu1
                case .us1_fed: return .us1_fed
                }
            }

            internal var rumEndpoint: RUMEndpoint {
                switch self {
                case .us1: return .us1
                case .us3: return .us3
                case .us5: return .us5
                case .eu1: return .eu1
                case .us1_fed: return .us1_fed
                }
            }
        }

        /// Determines the server for uploading logs.
        public enum LogsEndpoint {
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://app.datadoghq.com/).
            case us1
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://us3.datadoghq.com/).
            case us3
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://us5.datadoghq.com/).
            case us5
            /// Europe based servers.
            /// Sends logs to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu1
            /// US based servers, FedRAMP compatible.
            /// Sends logs to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case us1_fed
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends logs to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// Gov servers.
            /// Sends logs to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case gov
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                let endpoint = "api/v2/logs"
                switch self {
                case .us1, .us: return "https://logs.browser-intake-datadoghq.com/" + endpoint
                case .us3: return "https://logs.browser-intake-us3-datadoghq.com/" + endpoint
                case .us5: return "https://logs.browser-intake-us5-datadoghq.com/" + endpoint
                case .eu1, .eu: return "https://mobile-http-intake.logs.datadoghq.eu/" + endpoint
                case .us1_fed, .gov: return "https://logs.browser-intake-ddog-gov.com/" + endpoint
                case let .custom(url: url): return url
                }
            }
        }

        /// Determines the server for uploading traces.
        public enum TracesEndpoint {
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://app.datadoghq.com/).
            case us1
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://us3.datadoghq.com/).
            case us3
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://us5.datadoghq.com/).
            case us5
            /// Europe based servers.
            /// Sends traces to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu1
            /// US based servers, FedRAMP compatible.
            /// Sends traces to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case us1_fed
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends traces to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// Gov servers.
            /// Sends traces to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case gov
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                let endpoint = "api/v2/spans"
                switch self {
                case .us1, .us: return "https://trace.browser-intake-datadoghq.com/" + endpoint
                case .us3: return "https://trace.browser-intake-us3-datadoghq.com/" + endpoint
                case .us5: return "https://trace.browser-intake-us5-datadoghq.com/" + endpoint
                case .eu1, .eu: return "https:/public-trace-http-intake.logs.datadoghq.eu/" + endpoint
                case .us1_fed, .gov: return "https://trace.browser-intake-ddog-gov.com/" + endpoint
                case let .custom(url: url): return url
                }
            }
        }

        /// Determines the server for uploading RUM events.
        public enum RUMEndpoint {
            /// US based servers.
            /// Sends RUM events to [app.datadoghq.com](https://app.datadoghq.com/).
            case us1
            /// US based servers.
            /// Sends RUM events to [app.datadoghq.com](https://us3.datadoghq.com/).
            case us3
            /// US based servers.
            /// Sends RUM events to [app.datadoghq.com](https://us5.datadoghq.com/).
            case us5
            /// Europe based servers.
            /// Sends RUM events to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu1
            /// US based servers, FedRAMP compatible.
            /// Sends RUM events to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case us1_fed
            /// US based servers.
            /// Sends RUM events to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends RUM events to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// Gov servers.
            /// Sends RUM events to [app.ddog-gov.com](https://app.ddog-gov.com/).
            case gov
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                let endpoint = "api/v2/rum"
                switch self {
                case .us1, .us: return "https://rum.browser-intake-datadoghq.com/" + endpoint
                case .us3: return "https://rum.browser-intake-us3-datadoghq.com/" + endpoint
                case .us5: return "https://rum.browser-intake-us5-datadoghq.com/" + endpoint
                case .eu1, .eu: return "https://rum-http-intake.logs.datadoghq.eu/" + endpoint
                case .us1_fed, .gov: return "https://rum.browser-intake-ddog-gov.com/" + endpoint
                case let .custom(url: url): return url
                }
            }
        }

        /// The RUM Application ID.
        private(set) var rumApplicationID: String?
        /// Either the RUM client token (which supports RUM, Logging and APM) or regular client token, only for Logging and APM.
        private(set) var clientToken: String
        private(set) var environment: String
        private(set) var loggingEnabled: Bool
        private(set) var tracingEnabled: Bool
        private(set) var rumEnabled: Bool
        private(set) var crashReportingPlugin: DDCrashReportingPluginType?

        /// If `DatadogEndpoint` is set, it will override `logsEndpoint`, `tracesEndpoint` and `rumEndpoint` values.
        private(set) var datadogEndpoint: DatadogEndpoint?
        /// If `customLogsEndpoint` is set, it will override logs endpoint value configured with `logsEndpoint` and `DatadogEndpoint`.
        private(set) var customLogsEndpoint: URL?
        /// If `customTracesEndpoint` is set, it will override traces endpoint value configured with `tracesEndpoint` and `DatadogEndpoint`.
        private(set) var customTracesEndpoint: URL?
        /// If `customRUMEndpoint` is set, it will override rum endpoint value configured with `rumEndpoint` and `DatadogEndpoint`.
        private(set) var customRUMEndpoint: URL?

        /// Deprecated value
        private(set) var logsEndpoint: LogsEndpoint
        /// Deprecated value
        private(set) var tracesEndpoint: TracesEndpoint
        /// Deprecated value
        private(set) var rumEndpoint: RUMEndpoint

        private(set) var serviceName: String?
        private(set) var firstPartyHosts: Set<String>?
        private(set) var logEventMapper: LogEventMapper?
        private(set) var spanEventMapper: SpanEventMapper?
        private(set) var rumSessionsSamplingRate: Float
        private(set) var rumSessionsListener: RUMSessionListener?
        private(set) var rumUIKitViewsPredicate: UIKitRUMViewsPredicate?
        private(set) var rumUIKitUserActionsPredicate: UIKitRUMUserActionsPredicate?
        private(set) var rumLongTaskDurationThreshold: TimeInterval?
        private(set) var rumViewEventMapper: RUMViewEventMapper?
        private(set) var rumResourceEventMapper: RUMResourceEventMapper?
        private(set) var rumActionEventMapper: RUMActionEventMapper?
        private(set) var rumErrorEventMapper: RUMErrorEventMapper?
        private(set) var rumLongTaskEventMapper: RUMLongTaskEventMapper?
        private(set) var rumResourceAttributesProvider: URLSessionRUMAttributesProvider?
        private(set) var rumBackgroundEventTrackingEnabled: Bool
        private(set) var batchSize: BatchSize
        private(set) var uploadFrequency: UploadFrequency
        private(set) var additionalConfiguration: [String: Any]
        private(set) var proxyConfiguration: [AnyHashable: Any]?
        private(set) var encryption: DataEncryption?

        /// The client token autorizing internal monitoring data to be sent to Datadog org.
        private(set) var internalMonitoringClientToken: String?

        /// Creates the builder for configuring the SDK to work with RUM, Logging and Tracing features.
        /// - Parameter rumApplicationID: RUM Application ID obtained on Datadog website.
        /// - Parameter clientToken: the client token (generated for the RUM Application) obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(rumApplicationID: String, clientToken: String, environment: String) -> Builder {
            return Builder(rumApplicationID: rumApplicationID, clientToken: clientToken, environment: environment)
        }

        /// Creates the builder for configuring the SDK to work with Logging and Tracing features.
        /// - Parameter clientToken: client token obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(clientToken: String, environment: String) -> Builder {
            return Builder(rumApplicationID: nil, clientToken: clientToken, environment: environment)
        }

        /// `Datadog.Configuration` builder.
        ///
        /// Usage (to enable RUM, Logging and Tracing):
        ///
        ///     Datadog.Configuration.builderUsing(rumApplicationID:clientToken:environment:)
        ///                           ... // customize using builder methods
        ///                          .build()
        ///
        /// or (to only enable Logging and Tracing):
        ///
        ///     Datadog.Configuration.builderUsing(clientToken:environment:)
        ///                           ... // customize using builder methods
        ///                          .build()
        ///
        public class Builder {
            internal var configuration: Configuration

            /// Private initializer providing default configuration values.
            init(rumApplicationID: String?, clientToken: String, environment: String) {
                self.configuration = Configuration(
                    rumApplicationID: rumApplicationID,
                    clientToken: clientToken,
                    environment: environment,
                    loggingEnabled: true,
                    tracingEnabled: true,
                    rumEnabled: rumApplicationID != nil,
                    crashReportingPlugin: nil,
                    // While `.set(<feature>Endpoint:)` APIs are deprecated, the `datadogEndpoint` default must be `nil`,
                    // so we know the clear user's intent to override deprecated values.
                    datadogEndpoint: nil,
                    customLogsEndpoint: nil,
                    customTracesEndpoint: nil,
                    customRUMEndpoint: nil,
                    logsEndpoint: .us1,
                    tracesEndpoint: .us1,
                    rumEndpoint: .us1,
                    serviceName: nil,
                    firstPartyHosts: nil,
                    spanEventMapper: nil,
                    rumSessionsSamplingRate: 100.0,
                    rumSessionsListener: nil,
                    rumUIKitViewsPredicate: nil,
                    rumUIKitUserActionsPredicate: nil,
                    rumViewEventMapper: nil,
                    rumResourceEventMapper: nil,
                    rumActionEventMapper: nil,
                    rumErrorEventMapper: nil,
                    rumResourceAttributesProvider: nil,
                    rumBackgroundEventTrackingEnabled: false,
                    batchSize: .medium,
                    uploadFrequency: .average,
                    additionalConfiguration: [:],
                    proxyConfiguration: nil,
                    internalMonitoringClientToken: nil
                )
            }

            /// Sets the Datadog server endpoint where data is sent.
            ///
            /// If set, it will override values set by any of these deprecated APIs:
            /// * `set(logsEndpoint:)`
            /// * `set(tracesEndpoint:)`
            /// * `set(rumEndpoint:)`
            ///
            /// - Parameter endpoint: server endpoint (default value is `.us`)
            public func set(endpoint: DatadogEndpoint) -> Builder {
                configuration.datadogEndpoint = endpoint
                return self
            }

            /// Sets the custom server endpoint where Logs are sent.
            ///
            /// - Parameter endpoint: server endpoint (not set by default)
            public func set(customLogsEndpoint: URL) -> Builder {
                configuration.customLogsEndpoint = customLogsEndpoint
                return self
            }

            /// Sets the custom server endpoint where Spans are sent.
            ///
            /// - Parameter customTracesEndpoint: server endpoint (not set by default)
            public func set(customTracesEndpoint: URL) -> Builder {
                configuration.customTracesEndpoint = customTracesEndpoint
                return self
            }

            /// Sets the custom server endpoint where RUM events are sent.
            ///
            /// - Parameter customRUMEndpoint: server endpoint (not set by default)
            public func set(customRUMEndpoint: URL) -> Builder {
                configuration.customRUMEndpoint = customRUMEndpoint
                return self
            }

            // MARK: - Logging Configuration

            /// Enables or disables the logging feature.
            ///
            /// This option is meant to opt-out from using Datadog Logging entirely, no matter of your environment or build configuration. If you need to
            /// disable logging only for certain scenarios (e.g. in `DEBUG` build configuration), use `sendLogsToDatadog(false)` available
            /// on `Logger.Builder`.
            ///
            /// If `enableLogging(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the logging feature. This will give you additional performance optimization if you only use RUM or tracing.
            ///
            /// **NOTE**: If you use logging for tracing (`span.log(fields:)`) keep the logging feature enabled. Otherwise the logs
            /// you send for `span` objects won't be delivered to Datadog.
            ///
            /// - Parameter enabled: `true` by default
            public func enableLogging(_ enabled: Bool) -> Builder {
                configuration.loggingEnabled = enabled
                return self
            }

            /// Sets the custom mapper for `LogEvent`. This can be used to modify logs before they are send to Datadog.
            /// - Parameter mapper: the closure taking `LogEvent` as input and expecting `LogEvent` as output.
            /// The implementation should obtain a mutable version of the `LogEvent`, modify it and return it. Returning `nil` will result
            /// with dropping the Log event entirely, so it won't be send to Datadog.
            public func setLogEventMapper(_ mapper: @escaping (LogEvent) -> LogEvent?) -> Builder {
                configuration.logEventMapper = mapper
                return self
            }

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us`)
            @available(*, deprecated, message: "This option is replaced by `set(endpoint:)`. Refer to the new API comment for details.")
            public func set(logsEndpoint: LogsEndpoint) -> Builder {
                configuration.logsEndpoint = logsEndpoint
                return self
            }

            // MARK: - Tracing Configuration

            /// Enables or disables the tracing feature.
            ///
            /// This option is meant to opt-out from using Datadog Tracing entirely, no matter of your environment or build configuration. If you need to
            /// disable tracing only for certain scenarios (e.g. in `DEBUG` build configuration), do not set `Global.sharedTracer` to `Tracer`,
            /// and your app will be using the no-op tracer instance.
            ///
            /// If `enableTracing(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the tracing feature. This will give you additional performance optimization if you only use RUM or logging.
            ///
            /// - Parameter enabled: `true` by default
            public func enableTracing(_ enabled: Bool) -> Builder {
                configuration.tracingEnabled = enabled
                return self
            }

            /// Sets the server endpoint to which traces are sent.
            /// - Parameter tracesEndpoint: server endpoint (default value is `TracesEndpoint.us` )
            @available(*, deprecated, message: "This option is replaced by `set(endpoint:)`. Refer to the new API comment for details.")
            public func set(tracesEndpoint: TracesEndpoint) -> Builder {
                configuration.tracesEndpoint = tracesEndpoint
                return self
            }

            /// Configures network requests monitoring for Tracing and RUM features. **Must be used together with** `DDURLSessionDelegate` set as the `URLSession` delegate.
            @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
            public func set(tracedHosts: Set<String>) -> Builder {
                return track(firstPartyHosts: tracedHosts)
            }

            @available(*, deprecated, message: "This option is replaced by `trackURLSession(firstPartyHosts:)`. Refer to the new API comment for important details.")
            public func track(firstPartyHosts: Set<String>) -> Builder {
                return trackURLSession(firstPartyHosts: firstPartyHosts)
            }

            /// Configures network requests monitoring for Tracing and RUM features. **It must be used together with** `DDURLSessionDelegate` set as the `URLSession` delegate.
            ///
            /// If set, the SDK will intercept all network requests made by `URLSession` instances which use `DDURLSessionDelegate`.
            ///
            /// Each request will be classified as 1st- or 3rd-party based on the host comparison, i.e.:
            /// * if `firstPartyHosts` is `["example.com"]`:
            ///     - 1st-party URL examples: https://example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://foo.com/
            /// * if `firstPartyHosts` is `["api.example.com"]`:
            ///     - 1st-party URL examples: https://api.example.com/, https://api.example.com/v2/users
            ///     - 3rd-party URL examples: https://example.com/, https://foo.com/
            ///
            /// If RUM feature is enabled, the SDK will send RUM Resources for all intercepted requests.
            ///
            /// If Tracing feature is enabled, the SDK will send tracing Span for each 1st-party request. It will also add extra HTTP headers to further propagate the trace - it means that
            /// if your backend is instrumented with Datadog agent you will see the full trace (e.g.: client → server → database) in your dashboard, thanks to Datadog Distributed Tracing.
            ///
            /// If both RUM and Tracing features are enabled, the SDK will be sending RUM Resources for 1st- and 3rd-party requests and tracing Spans for 1st-parties.
            ///
            /// Until `trackURLSession()` is called, network requests monitoring is disabled.
            ///
            /// **NOTE 1:** Enabling this option will install swizzlings on some methods of the `URLSession`. Refer to `URLSessionSwizzler.swift`
            /// for implementation details.
            ///
            /// **NOTE 2:** The `URLSession` instrumentation will NOT work without using `DDURLSessionDelegate`.
            ///
            /// - Parameter firstPartyHosts: empty set by default
            public func trackURLSession(firstPartyHosts: Set<String> = []) -> Builder {
                configuration.firstPartyHosts = firstPartyHosts
                return self
            }

            /// Sets the custom mapper for `SpanEvent`. This can be used to modify spans before they are send to Datadog.
            /// - Parameter mapper: the closure taking `SpanEvent` as input and expecting `SpanEvent` as output.
            /// The implementation should obtain a mutable version of the `SpanEvent`, modify it and return it.
            ///
            /// **NOTE** The mapper intentionally prevents from returning a `nil` to drop the `SpanEvent` entirely, this ensures that all spans are sent to Datadog.
            ///
            /// Use the `trackURLSession(firstPartyHosts:)` API to configure tracing only the hosts that you are interested in.
            public func setSpanEventMapper(_ mapper: @escaping (SpanEvent) -> SpanEvent) -> Builder {
                configuration.spanEventMapper = mapper
                return self
            }

            // MARK: - RUM Configuration

            /// Enables or disables the RUM feature.
            ///
            /// This option is meant to opt-out from using Datadog RUM entirely, no matter of your environment or build configuration. If you need to
            /// disable RUM only for certain scenarios (e.g. in `DEBUG` build configuration), you may prefer to not register `RUMMonitor` on `Global.rum`
            /// and let your app use the no-op monitor instance.
            ///
            /// If `enableRUM(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the RUM feature. This will give you additional performance optimization if you only use logging and/or tracing.
            ///
            /// **NOTE**: This setting only applies if you use `Datadog.Configuration.builderUsing(rumApplicationID:rumClientToken:environment:)`.
            /// When using other constructors for obtaining the builder, RUM is disabled by default.
            ///
            /// - Parameter enabled: `true` by default when using `Datadog.Configuration.builderUsing(rumApplicationID:rumClientToken:environment:)`.
            /// `false` otherwise.
            public func enableRUM(_ enabled: Bool) -> Builder {
                configuration.rumEnabled = enabled
                return self
            }

            /// Sets the server endpoint to which RUM events are sent.
            /// - Parameter rumEndpoint: server endpoint (default value is `RUMEndpoint.us` )
            @available(*, deprecated, message: "This option is replaced by `set(endpoint:)`. Refer to the new API comment for details.")
            public func set(rumEndpoint: RUMEndpoint) -> Builder {
                configuration.rumEndpoint = rumEndpoint
                return self
            }

            /// Sets the sampling rate for RUM Sessions.
            ///
            /// - Parameter rumSessionsSamplingRate: the sampling rate must be a value between `0.0` and `100.0`. A value of `0.0`
            /// means no RUM events will be sent, `100.0` means all sessions will be kept (default value is `100.0`).
            public func set(rumSessionsSamplingRate: Float) -> Builder {
                configuration.rumSessionsSamplingRate = rumSessionsSamplingRate
                return self
            }

            /// Sets the RUM Session start callback.
            ///
            /// The callback takes 2 arguments: the newly started Session ID and a boolean indicating whether or not the session is discarded by the sampling rate
            /// (when `true` it means no event in this session will be kept).
            ///
            /// - Parameter handler: the callback handler to notify whenever a new Session starts.
            public func onRUMSessionStart(_ handler: @escaping (String, Bool) -> Void) -> Builder {
                configuration.rumSessionsListener = handler
                return self
            }

            /// Sets the predicate for automatically tracking `UIViewControllers` as RUM Views.
            ///
            /// When the app is running, the SDK will ask provided `predicate` if any noticed `UIViewController` should be considered
            /// as the RUM View. The `predicate` implementation should return RUM View parameters if the `UIViewController` indicates
            /// the RUM View or `nil` otherwise.
            ///
            /// **NOTE:** Enabling this option will install swizzlings on `UIViewController's` lifecycle methods. Refer
            /// to `UIViewControllerSwizzler.swift` for implementation details.
            ///
            /// Until this option is enabled, automatic tracking of `UIViewControllers` is disabled and no swizzlings are installed on the `UIViewController` class.
            ///
            /// - Parameter predicate: the predicate deciding if a given `UIViewController` marks the beginning or end of the RUM View.
            /// Defaults to `DefaultUIKitRUMViewsPredicate` instance.
            public func trackUIKitRUMViews(using predicate: UIKitRUMViewsPredicate = DefaultUIKitRUMViewsPredicate()) -> Builder {
                configuration.rumUIKitViewsPredicate = predicate
                return self
            }

            /// Enables or disables automatic tracking of `UITouch` events as RUM Actions.
            ///
            /// When enabled, the SDK will track `UIEvents` send to the application and capture `UIViews` and `UIControls` that user interacted with.
            /// It will send RUM Action for each recognized element. Any touch events on the keyboard are ignored for privacy.
            ///
            /// The RUM Action will be named by the name of the interacted element's class and will be extended with `accessibilityIdentifier` (if set) for more context.
            ///
            /// **NOTE:** Enabling this option will install swizzlings on `UIApplication.sendEvent(_:)` method. Refer
            /// to `UIApplicationSwizzler.swift` for implementation details.
            ///
            /// Until this option is enabled, automatic tracking of `UIEvents` is disabled and no swizzling is installed on the `UIApplication` class.
            ///
            /// - Parameter enabled: `true` by default
            @available(*, deprecated, message: "This option is replaced by `trackUIKitRUMActions(using:)`. Refer to the new API comment for details.")
            public func trackUIKitActions(_ enabled: Bool = true) -> Builder {
                if enabled {
                    return self.trackUIKitRUMActions()
                }
                return self
            }

            /// Enables automatic tracking of `UITouch` events as RUM Actions.
            ///
            /// When enabled, the SDK will track `UIEvents` send to the application and capture `UIViews` and `UIControls` that user interacted with.
            /// It will send RUM Action for each recognized element. Any touch events on the keyboard are ignored for privacy.
            ///
            /// The RUM Action will be named by the name of the interacted element's class and will be extended with `accessibilityIdentifier` (if set) for more context.
            ///
            /// **NOTE:** Enabling this option will install swizzlings on `UIApplication.sendEvent(_:)` method. Refer
            /// to `UIApplicationSwizzler.swift` for implementation details.
            ///
            /// Until this option is enabled, automatic tracking of `UIEvents` is disabled and no swizzling is installed on the `UIApplication` class.
            ///
            /// - Parameter predicate: predicate deciding if a given action should be recorded and which allows to give custom name and to add custom attributes to the RUM Action.
            /// Defaults to `DefaultUIKitRUMUserActionsPredicate` instance.
            public func trackUIKitRUMActions(using predicate: UIKitRUMUserActionsPredicate = DefaultUIKitRUMUserActionsPredicate()) -> Builder {
                configuration.rumUIKitUserActionsPredicate = predicate
                return self
            }

            /// Enable long operations on the main thread to be tracked automatically.
            /// Any long running operation on the main thread will appear as Long Tasks in Datadog RUM Explorer.
            /// - Parameter threshold: the threshold in seconds above which a task running on the Main thread is considered as a long task (default 0.1 second)
            public func trackRUMLongTasks(threshold: TimeInterval = 0.1) -> Builder {
                configuration.rumLongTaskDurationThreshold = threshold
                return self
            }

            /// Sets the custom mapper for `RUMViewEvent`. This can be used to modify RUM View events before they are send to Datadog.
            /// - Parameter mapper: the closure taking `RUMViewEvent` as input and expecting `RUMViewEvent` as output.
            /// The implementation should obtain a mutable version of the `RUMViewEvent`, modify it and return it.
            ///
            /// **NOTE** The mapper intentionally prevents from returning a `nil` to drop the `RUMViewEvent` entirely, this ensures that all `RUMViewEvent` are sent to Datadog.
            ///
            /// Use the `UIKitRUMViewsPredicate` API to ensure upstream consideration or filtering out of `UIViewController`/`RUMView`s.
            public func setRUMViewEventMapper(_ mapper: @escaping (RUMViewEvent) -> RUMViewEvent) -> Builder {
                configuration.rumViewEventMapper = mapper
                return self
            }

            /// Sets the custom mapper for `RUMResourceEvent`. This can be used to modify RUM Resource events before they are send to Datadog.
            /// - Parameter mapper: the closure taking `RUMResourceEvent` as input and expecting `RUMResourceEvent` or `nil` as output.
            /// The implementation should obtain a mutable version of the `RUMResourceEvent`, modify it and return. Returning `nil` will result
            /// with dropping the RUM Resource event entirely, so it won't be send to Datadog.
            public func setRUMResourceEventMapper(_ mapper: @escaping (RUMResourceEvent) -> RUMResourceEvent?) -> Builder {
                configuration.rumResourceEventMapper = mapper
                return self
            }

            /// Sets the custom mapper for `RUMActionEvent`. This can be used to modify RUM Action events before they are send to Datadog.
            /// - Parameter mapper: the closure taking `RUMActionEvent` as input and expecting `RUMActionEvent` or `nil` as output.
            /// The implementation should obtain a mutable version of the `RUMActionEvent`, modify it and return. Returning `nil` will result
            /// with dropping the RUM Action event entirely, so it won't be send to Datadog.
            public func setRUMActionEventMapper(_ mapper: @escaping (RUMActionEvent) -> RUMActionEvent?) -> Builder {
                configuration.rumActionEventMapper = mapper
                return self
            }

            /// Sets the custom mapper for `RUMErrorEvent`. This can be used to modify RUM Error events before they are send to Datadog.
            /// - Parameter mapper: the closure taking `RUMErrorEvent` as input and expecting `RUMErrorEvent` or `nil` as output.
            /// The implementation should obtain a mutable version of the `RUMErrorEvent`, modify it and return. Returning `nil` will result
            /// with dropping the RUM Error event entirely, so it won't be send to Datadog.
            public func setRUMErrorEventMapper(_ mapper: @escaping (RUMErrorEvent) -> RUMErrorEvent?) -> Builder {
                configuration.rumErrorEventMapper = mapper
                return self
            }

            /// Sets the custom mapper for `RUMLongTaskEvent`. This can be used to modify RUM Long Task events before they are send to Datadog.
            /// - Parameter mapper: the closure taking `RUMLongTaskEvent` as input and expecting `RUMLongTaskEvent` or `nil` as output.
            /// The implementation should obtain a mutable version of the `RUMLongTaskEvent`, modify it and return. Returning `nil` will result
            /// with dropping the RUM Long Task event entirely, so it won't be send to Datadog.
            public func setRUMLongTaskEventMapper(_ mapper: @escaping (RUMLongTaskEvent) -> RUMLongTaskEvent?) -> Builder {
                configuration.rumLongTaskEventMapper = mapper
                return self
            }

            /// Sets a closure to provide custom attributes for intercepted RUM Resources.
            ///
            /// The `provider` closure is called for each `URLSession` task intercepted by the SDK (each automatically collected RUM Resource).
            /// The closure is called with session task information (`URLRequest`, `URLResponse?`, `Data?` and `Error?`) that can be used to identify the task, inspect its
            /// values and return custom attributes for the RUM Resource.
            ///
            /// - Parameter provider: the closure called for each RUM Resource collected by the SDK. This closure is called with task information and may return custom attributes
            ///                       for the RUM Resource or `nil` if no attributes should be attached.
            public func setRUMResourceAttributesProvider(_ provider: @escaping (URLRequest, URLResponse?, Data?, Error?) -> [AttributeKey: AttributeValue]?) -> Builder {
                configuration.rumResourceAttributesProvider = provider
                return self
            }

            /// Enables or disables automatic tracking of background events (events hapenning when no `UIViewController` is active).
            ///
            /// When enabled, the SDK will track RUM Events into an automatically created Background RUM View (named `Background`)
            ///
            /// **NOTE:** Enabling this option might increase the number of session tracked, and increase your billing.
            ///
            /// Until this option is enabled, automatic tracking of  background event is disabled.
            ///
            /// - Parameter enabled: `true` by default
            public func trackBackgroundEvents(_ enabled: Bool = true) -> Builder {
                configuration.rumBackgroundEventTrackingEnabled = enabled
                return self
            }

            // MARK: - Crash Reporting Configuration

            /// Enables the crash reporting feature.
            ///
            /// To enable Datadog crash reporting, configure this option by passing the `crashReportingPlugin`.
            /// The plugin must be obtained from `DatadogCrashReporting` library:
            ///
            ///         import DatadogCrashReporting
            ///
            ///         .enableCrashReporting(using: DDCrashReportingPlugin())
            ///
            /// - Parameter crashReportingPlugin: `nil` by default (Datadog crash reporting is disabled by default)
            public func enableCrashReporting(using crashReportingPlugin: DDCrashReportingPluginType) -> Builder {
                configuration.crashReportingPlugin = crashReportingPlugin
                return self
            }

#if DD_SDK_ENABLE_INTERNAL_MONITORING
            // MARK: - Internal Monitoring Configuration

            /// Enables the internal monitoring feature.
            ///
            /// This feature provides an observability for the SDK performance. All telemetry collected by the internal monitoring feature is sent to
            /// Datadog instance authorised for given `clientToken`, which can be a different org than the one configured for RUM, Tracing and Logging data.
            ///
            /// This feature is opt-in and requires specific configuration to be enabled. **Datadog does not collect any internal telemetry data by default.**
            ///
            /// To make this API visible, the `DD_SDK_ENABLE_INTERNAL_MONITORING` compiler flag must be defined in the  "Active Compilation Conditions" Build Setting
            /// or in the `.xcconfig` set for the build configuration:
            ///
            ///     SWIFT_ACTIVE_COMPILATION_CONDITIONS = DD_SDK_ENABLE_INTERNAL_MONITORING
            ///
            /// - Parameter clientToken: the client token authorised for a Datadog org which should receive the SDK telemetry
            public func enableInternalMonitoring(clientToken: String) -> Builder {
                configuration.internalMonitoringClientToken = clientToken
                return self
            }
#endif

            // MARK: - Features Common Configuration

            /// Sets the default service name associated with data send to Datadog.
            /// NOTE: The `serviceName` can be also overwritten by each `Logger` instance.
            /// - Parameter serviceName: the service name (default value is set to application bundle identifier)
            public func set(serviceName: String) -> Builder {
                configuration.serviceName = serviceName
                return self
            }

            /// Sets the preferred size of batched data uploaded to Datadog servers.
            /// This value impacts the size and number of requests performed by the SDK.
            /// - Parameter batchSize: `.medium` by default.
            public func set(batchSize: BatchSize) -> Builder {
                configuration.batchSize = batchSize
                return self
            }

            /// Sets the preferred frequency of uploading data to Datadog servers.
            /// This value impacts the frequency of performing network requests by the SDK.
            /// - Parameter uploadFrequency: `.average` by default.
            public func set(uploadFrequency: UploadFrequency) -> Builder {
                configuration.uploadFrequency = uploadFrequency
                return self
            }

            /// Sets proxy configuration attributes.
            /// This can be used to a enable a custom proxy for uploading tracked data to Datadog's intake.
            /// - Parameter proxyConfiguration: `nil` by default.
            public func set(proxyConfiguration: [AnyHashable: Any]?) -> Builder {
                configuration.proxyConfiguration = proxyConfiguration
                return self
            }

            /// Sets additional configuration attributes.
            /// This can be used to tweak internal features of the SDK.
            /// - Parameter additionalConfiguration: `[:]` by default.
            public func set(additionalConfiguration: [String: Any]) -> Builder {
                configuration.additionalConfiguration = additionalConfiguration
                return self
            }

            /// Sets data encryption to use for on-disk data persistency.
            /// - Parameter encryption: An encryption object complying with `DataEncryption` protocol.
            public func set(encryption: DataEncryption) -> Builder {
                configuration.encryption = encryption
                return self
            }

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return configuration
            }
        }
    }
}
