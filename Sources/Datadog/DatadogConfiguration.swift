import Foundation

extension Datadog {
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

        internal let logsUploadURL: DataUploadURL

        public static func builderUsing(clientToken: String) -> Builder {
            return Builder(clientToken: clientToken)
        }

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

            public func build() -> Configuration {
                do {
                    return try buildOrThrow()
                } catch {
                    userLogger.critical("\(error)")

                    // TODO: RUMM-171 Fail silently when misusing SDK public API
                    fatalError("`Logger` cannot be built: \(error)") // crash
                }
            }

            internal func buildOrThrow() throws -> Configuration {
                return Datadog.Configuration(
                    logsUploadURL: try DataUploadURL(endpointURL: logsEndpoint.url, clientToken: clientToken)
                )
            }
        }
    }
}
