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

        /// Determines server to which traces are sent.
        public enum TracesEndpoint {
            /// US based servers.
            /// Sends traces to [app.datadoghq.com](https://app.datadoghq.com/).
            case us // swiftlint:disable:this identifier_name
            /// Europe based servers.
            /// Sends traces to [app.datadoghq.eu](https://app.datadoghq.eu/).
            case eu // swiftlint:disable:this identifier_name
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
        internal let logsEndpoint: LogsEndpoint
        internal let tracesEndpoint: TracesEndpoint

        /// Creates configuration builder and sets client token.
        /// - Parameter clientToken: client token obtained on Datadog website.
        public static func builderUsing(clientToken: String) -> Builder {
            return Builder(clientToken: clientToken)
        }

        /// `Datadog.Configuration` builder.
        ///
        /// Usage:
        ///
        ///     Datadog.Configuration.builderUsing(clientToken: "<client token>")
        ///                           ... // customize using builder methods
        ///                          .build()
        ///
        public class Builder {
            private let clientToken: String
            private var logsEndpoint: LogsEndpoint
            private var tracesEndpoint: TracesEndpoint

            internal init(clientToken: String) {
                self.clientToken = clientToken
                self.logsEndpoint = .us
                self.tracesEndpoint = .us
            }

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us` )
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

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return Configuration(
                    clientToken: clientToken,
                    logsEndpoint: logsEndpoint,
                    tracesEndpoint: tracesEndpoint
                )
            }
        }
    }
}
