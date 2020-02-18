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

        /// Logs upload URL or `nil` if user configuration is invalid.
        internal let logsUploadURL: DataUploadURL?

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

            internal init(clientToken: String) {
                self.clientToken = clientToken
                self.logsEndpoint = .us
            }

            /// Sets the server endpoint to which logs are sent.
            /// - Parameter logsEndpoint: server endpoint (default value is `LogsEndpoint.us` )
            public func set(logsEndpoint: LogsEndpoint) -> Builder {
                self.logsEndpoint = logsEndpoint
                return self
            }

            /// Builds `Datadog.Configuration` object.
            public func build() -> Configuration {
                return Configuration(
                    logsUploadURL: try? DataUploadURL(endpointURL: logsEndpoint.url, clientToken: clientToken)
                )
            }
        }
    }
}
