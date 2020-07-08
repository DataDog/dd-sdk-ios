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
        /// Determines server to which logs are sent.
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

        /// Determines server to which traces are sent.
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

        internal let clientToken: String
        internal let environment: String
        internal var loggingEnabled: Bool
        internal var tracingEnabled: Bool
        internal let logsEndpoint: LogsEndpoint
        internal var tracesEndpoint: TracesEndpoint
        internal let serviceName: String?
        internal var tracedHosts = Set<String>()

        /// Creates configuration builder and sets client token.
        /// - Parameter clientToken: client token obtained on Datadog website.
        /// - Parameter environment: the environment name which will be sent to Datadog. This can be used
        ///  to filter events on different environments (e.g. "staging" or "production").
        public static func builderUsing(clientToken: String, environment: String) -> Builder {
            return Builder(clientToken: clientToken, environment: environment)
        }

        /// `Datadog.Configuration` builder.
        ///
        /// Usage:
        ///
        ///     Datadog.Configuration.builderUsing(clientToken: "<client token>", environment: "<env name>")
        ///                           ... // customize using builder methods
        ///                          .build()
        ///
        public class Builder {
            internal let clientToken: String
            internal let environment: String
            internal var loggingEnabled = true
            internal var tracingEnabled = true
            internal var logsEndpoint: LogsEndpoint = .us
            internal var tracesEndpoint: TracesEndpoint = .us
            internal var serviceName: String? = nil
            internal var tracedHosts = Set<String>()

            internal init(clientToken: String, environment: String) {
                self.clientToken = clientToken
                self.environment = environment
            }

            // MARK: - Features Configuration

            /// Enables or disables the logging feature.
            ///
            /// This option is meant to opt-out from using Datadog Logging entirely, no matter of your environment or build configuration. If you need to
            /// disable logging only for certain scenarios (e.g. in `DEBUG` build configuration), use `sendLogsToDatadog(false)` available
            /// on `Logger.Builder`.
            ///
            /// If `enableLogging(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the logging feature. This will give you additional performance optimization if you only use tracing, but not logging.
            ///
            /// **NOTE**: If you use logging for tracing (`span.log(fields:)`) keep the logging feature enabled. Otherwise the logs
            /// you send for `span` objects won't be delivered to Datadog.
            ///
            /// - Parameter enabled: `true` by default
            public func enableLogging(_ enabled: Bool) -> Builder {
                self.loggingEnabled = enabled
                return self
            }

            /// Enables or disables the tracing feature.
            ///
            /// This option is meant to opt-out from using Datadog Tracing entirely, no matter of your environment or build configuration. If you need to
            /// disable tracing only for certain scenarios (e.g. in `DEBUG` build configuration), do not set `Global.sharedTracer` to `Tracer`,
            /// and your app will be using the no-op tracer instance.
            ///
            /// If `enableTracing(false)` is set, the SDK won't instantiate underlying resources required for
            /// running the tracing feature. This will give you additional performance optimization if you only use logging, but not tracing.
            ///
            /// - Parameter enabled: `true` by default
            public func enableTracing(_ enabled: Bool) -> Builder {
                self.tracingEnabled = enabled
                return self
            }

            /// Sets the hosts to be automatically traced.
            ///
            /// Every request made to a traced host and its subdomains will create its Span with related information; _such as url, method, status code, error (if any)_.
            /// Example, if `tracedHosts` is ["example.com"], then every network request such as the ones below will be automatically traced and generate a span.
            /// "https://example.com/any/path"
            /// "https://api.example.com/any/path"
            ///
            /// If your backend is also being traced with Datadog agents, you can see the full trace (eg: client>server>database) in your dashboard with our distributed tracing feature.
            /// A few HTTP headers are injected to auto-traced network requests so that you can see your spans in your backend as well.
            ///
            /// If `tracedHosts` is empty, automatic tracing is disabled.
            /// **IMPORTANT:** Non-empty `tracedHost`s will lead to modifying implementation of some `URLSession` methods, in case your app relies on `URLSession` internals please refer to `URLSessionSwizzler.swift` file for details
            ///
            /// - Parameter tracedHosts: empty by default
            public func set(tracedHosts: Set<String>) -> Builder {
                self.tracedHosts = tracedHosts
                return self
            }

            // MARK: - Endpoints Configuration

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us`)
            public func set(logsEndpoint: LogsEndpoint) -> Builder {
                self.logsEndpoint = logsEndpoint
                return self
            }

            /// Sets the server endpoint to which traces are sent.
            /// - Parameter tracesEndpoint: server endpoint (default value is `TracesEndpoint.us` )
            public func set(tracesEndpoint: TracesEndpoint) -> Builder {
                self.tracesEndpoint = tracesEndpoint
                return self
            }

            // MARK: - Other Settings

            /// Sets the default service name associated with data send to Datadog.
            /// NOTE: The `serviceName` can be also overwriten by each `Logger` instance.
            /// - Parameter serviceName: the service name (default value is set to application bundle identifier)
            public func set(serviceName: String) -> Builder {
                self.serviceName = serviceName
                return self
            }

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return Configuration(
                    clientToken: clientToken,
                    environment: environment,
                    loggingEnabled: loggingEnabled,
                    tracingEnabled: tracingEnabled,
                    logsEndpoint: logsEndpoint,
                    tracesEndpoint: tracesEndpoint,
                    serviceName: serviceName,
                    tracedHosts: tracedHosts
                )
            }
        }
    }

    /// Valid SDK configuration, passed to the features.
    ///
    /// It takes two types received from the user: `Datadog.Configuration` and `AppContext` and blends them together
    /// with resolving defaults and ensuring the configuration consistency.
    internal struct ValidConfiguration {
        internal let applicationName: String
        internal let applicationVersion: String
        internal let applicationBundleIdentifier: String
        internal let serviceName: String
        internal let environment: String

        internal let logsUploadURLWithClientToken: URL
        internal let tracesUploadURLWithClientToken: URL
    }
}

extension Datadog.ValidConfiguration {
    init(configuration: Datadog.Configuration, appContext: AppContext) throws {
        self.init(
            applicationName: appContext.bundleName ?? appContext.bundleType.rawValue,
            applicationVersion: appContext.bundleVersion ?? "0.0.0",
            applicationBundleIdentifier: appContext.bundleIdentifier ?? "unknown",
            serviceName: configuration.serviceName ?? appContext.bundleIdentifier ?? "ios",
            environment: try ifValid(environment: configuration.environment),
            logsUploadURLWithClientToken: try ifValid(
                endpointURLString: configuration.logsEndpoint.url,
                clientToken: configuration.clientToken
            ),
            tracesUploadURLWithClientToken: try ifValid(
                endpointURLString: configuration.tracesEndpoint.url,
                clientToken: configuration.clientToken
            )
        )
    }
}

private func ifValid(environment: String) throws -> String {
    let regex = #"^[a-zA-Z0-9_]+$"#
    if environment.range(of: regex, options: .regularExpression, range: nil, locale: nil) == nil {
        throw ProgrammerError(description: "`environment` contains illegal characters (only alphanumerics and `_` are allowed)")
    }
    return environment
}

private func ifValid(endpointURLString: String, clientToken: String) throws -> URL {
    guard let endpointURL = URL(string: endpointURLString) else {
        throw ProgrammerError(description: "The `url` in `.custom(url:)` must be a valid URL string.")
    }
    guard !clientToken.isEmpty else {
        throw ProgrammerError(description: "`clientToken` cannot be empty.")
    }
    let endpointURLWithClientToken = endpointURL.appendingPathComponent(clientToken)
    guard let url = URL(string: endpointURLWithClientToken.absoluteString) else {
        throw ProgrammerError(description: "Cannot build upload URL.")
    }
    return url
}
