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
        /// Determines the server for uploading logs.
        public enum LogsEndpoint {
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends logs to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                switch self {
                case .us: return "https://mobile-http-intake.logs.datadoghq.com/v1/input/"
                case .eu: return "https://mobile-http-intake.logs.datadoghq.eu/v1/input/"
                case let .custom(url: url): return url
                }
            }
        }

        /// Determines the server for uploading traces.
        public enum TracesEndpoint {
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends traces to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                switch self {
                case .us: return "https://public-trace-http-intake.logs.datadoghq.com/v1/input/"
                case .eu: return "https://public-trace-http-intake.logs.datadoghq.eu/v1/input/"
                case let .custom(url: url): return url
                }
            }
        }

        /// Determines the server for uploading RUM events.
        public enum RUMEndpoint {
            /// US based servers.
            /// Sends RUM events to [app.datadoghq.com](https://app.datadoghq.com/).
            case us
            /// Europe based servers.
            /// Sends RUM events to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu
            /// User-defined server.
            case custom(url: String)

            internal var url: String {
                switch self {
                case .us: return "https://rum-http-intake.logs.datadoghq.com/v1/input/"
                case .eu: return "https://rum-http-intake.logs.datadoghq.eu/v1/input/"
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
        private(set) var logsEndpoint: LogsEndpoint
        private(set) var tracesEndpoint: TracesEndpoint
        private(set) var rumEndpoint: RUMEndpoint
        private(set) var serviceName: String?
        private(set) var tracedHosts: Set<String>
        private(set) var rumSessionsSamplingRate: Float

        /// Creates the builder for configuring the SDK to work with RUM, Logging and Tracing features.
        /// - Parameter rumApplicationID: RUM Application ID obtained on Datadog website.
        /// - Parameter rumClientToken: RUM Client Token (generated for the RUM Application ID) obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(rumApplicationID: String, rumClientToken: String, environment: String) -> Builder {
            return Builder(rumApplicationID: rumApplicationID, rumClientToken: rumClientToken, environment: environment)
        }

        /// Creates the builder for configuring the SDK to work with Logging and Tracing features.
        /// - Parameter clientToken: client token obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(clientToken: String, environment: String) -> Builder {
            return Builder(clientToken: clientToken, environment: environment)
        }

        /// `Datadog.Configuration` builder.
        ///
        /// Usage (to enable RUM, Logging and Tracing):
        ///
        ///     Datadog.Configuration.builderUsing(rumApplicationID:rumClientToken:environment:)
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

            /// Initializer invoked when initializing the SDK to use any of (including all): RUM, Logging, Tracing.
            internal convenience init(rumApplicationID: String, rumClientToken: String, environment: String) {
                self.init(rumApplicationID: rumApplicationID, clientToken: rumClientToken, environment: environment)
            }

            /// Initializer invoked when initializing the SDK to use any of: Logging, Tracing.
            internal convenience init(clientToken: String, environment: String) {
                self.init(rumApplicationID: nil, clientToken: clientToken, environment: environment)
            }

            /// Private initializer providing default configuration values.
            private init(rumApplicationID: String?, clientToken: String, environment: String) {
                self.configuration = Configuration(
                    rumApplicationID: rumApplicationID,
                    clientToken: clientToken,
                    environment: environment,
                    loggingEnabled: true,
                    tracingEnabled: true,
                    rumEnabled: rumApplicationID != nil,
                    logsEndpoint: .us,
                    tracesEndpoint: .us,
                    rumEndpoint: .us,
                    serviceName: nil,
                    tracedHosts: [],
                    rumSessionsSamplingRate: 100.0
                )
            }

            // MARK: - Features Configuration

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

            /// Enables or disables the tracing feature.
            ///
            /// This option is meant to opt-out from using Datadog Tracing entirely, no matter of your environment or build configuration. If you need to
            /// disable tracing only for certain scenarios (e.g. in `DEBUG` build configuration), do not set `Global.sharedTracer` to `Tracer`,
            /// and your app will be using the no-op tracer instance.
            ///
            /// If `enableTracing(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the tracing feature. This will give you additional performance optimization if you only use RUM or tracing.
            ///
            /// - Parameter enabled: `true` by default
            public func enableTracing(_ enabled: Bool) -> Builder {
                configuration.tracingEnabled = enabled
                return self
            }

            /// Enables or disables the RUM feature.
            ///
            /// This option is meant to opt-out from using Datadog RUM entirely, no matter of your environment or build configuration. If you need to
            /// disable RUM only for certain scenarios (e.g. in `DEBUG` build configuration), do not set `Global.rum` to `RUMMonitor`,
            /// and your app will be using the no-op monitor instance.
            ///
            /// If `enableRUM(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the RUM feature. This will give you additional performance optimization if you only use logging or tracing.
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

            /// Sets the hosts to be automatically traced.
            ///
            /// Every request made to a traced host and its subdomains will create its Span with related information; _such as url, method, status code, error (if any)_.
            /// Example, if `tracedHosts` is `["example.com"]`, then every network request such as the ones below will be automatically traced and generate a span:
            /// * https://example.com/any/path
            /// * https://api.example.com/any/path
            ///
            /// If your backend is also being traced with Datadog agents, you can see the full trace (e.g.: client → server → database) in your dashboard with our distributed tracing feature.
            /// A few HTTP headers are injected to auto-traced network requests so that you can see your spans in your backend as well.
            ///
            /// If `tracedHosts` is empty, automatic tracing is disabled.
            ///
            /// **NOTE:** Non-empty `tracedHost`s will lead to modifying implementation of some `URLSession` methods, in case your app relies on `URLSession` internals please refer to `URLSessionSwizzler.swift` file for details
            ///
            /// - Parameter tracedHosts: empty by default
            public func set(tracedHosts: Set<String>) -> Builder {
                configuration.tracedHosts = tracedHosts
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

            // MARK: - Endpoints Configuration

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us`)
            public func set(logsEndpoint: LogsEndpoint) -> Builder {
                configuration.logsEndpoint = logsEndpoint
                return self
            }

            /// Sets the server endpoint to which traces are sent.
            /// - Parameter tracesEndpoint: server endpoint (default value is `TracesEndpoint.us` )
            public func set(tracesEndpoint: TracesEndpoint) -> Builder {
                configuration.tracesEndpoint = tracesEndpoint
                return self
            }

            /// Sets the server endpoint to which RUM events are sent.
            /// - Parameter rumEndpoint: server endpoint (default value is `RUMEndpoint.us` )
            public func set(rumEndpoint: RUMEndpoint) -> Builder {
                configuration.rumEndpoint = rumEndpoint
                return self
            }

            // MARK: - Other Settings

            /// Sets the default service name associated with data send to Datadog.
            /// NOTE: The `serviceName` can be also overwriten by each `Logger` instance.
            /// - Parameter serviceName: the service name (default value is set to application bundle identifier)
            public func set(serviceName: String) -> Builder {
                configuration.serviceName = serviceName
                return self
            }

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return configuration
            }
        }
    }
}
