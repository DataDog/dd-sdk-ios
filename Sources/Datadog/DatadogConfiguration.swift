/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

extension Datadog {
    /// Datadog SDK configuration.
    public struct Configuration {
        /// Determines server to which logs are sent.
        public enum LogsEndpoint {
            /// US based servers.
            /// Sends logs to [app.datadoghq.com](https://app.datadoghq.com/).
            case us // swiftlint:disable:this identifier_name
            /// Europe based servers.
            /// Sends logs to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu // swiftlint:disable:this identifier_name
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

        internal let clientToken: String
        internal let logsEndpoint: LogsEndpoint
        internal let serviceName: String?
        internal let environment: String

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
            internal var serviceName: String? = nil
            internal var logsEndpoint: LogsEndpoint = .us

            internal init(clientToken: String, environment: String) {
                self.clientToken = clientToken
                self.environment = environment
            }

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us`)
            public func set(logsEndpoint: LogsEndpoint) -> Builder {
                self.logsEndpoint = logsEndpoint
                return self
            }

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
                    logsEndpoint: logsEndpoint,
                    serviceName: serviceName,
                    environment: environment
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
