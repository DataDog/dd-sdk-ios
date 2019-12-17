import Foundation

/// An exception thrown during Datadog SDK initialization if configuration is invalid. Check `description` for details.
public struct DatadogInitializationException: Error {
    /// Describes the reason of failed initialization.
    public let description: String
}

/// Datadog SDK configuration object.
public struct Datadog {
    /// URL to upload logs to.
    internal let logsUploadURL: URL
    
    public init(
        logsEndpoint: String,
        clientToken: String
    ) throws {
        self.logsUploadURL = try buildLogsUploadURLOrThrow(logsEndpoint: logsEndpoint, clientToken: clientToken)
    }
}

private func buildLogsUploadURLOrThrow(logsEndpoint: String, clientToken: String) throws -> URL {
    guard !logsEndpoint.isEmpty else {
        throw DatadogInitializationException(description: "`logsEndpoint` cannot be empty.")
    }
    guard !clientToken.isEmpty else {
        throw DatadogInitializationException(description: "`clientToken` cannot be empty.")
    }
    guard let endpointWithClientToken = URL(string: logsEndpoint)?.appendingPathComponent(clientToken) else {
        throw DatadogInitializationException(description: "Invalid `logsEndpoint` or `clientToken`.")
    }
    guard let url = URL(string: "\(endpointWithClientToken.absoluteString)?ddsource=mobile") else {
        throw DatadogInitializationException(description: "Cannot build logs upload URL.")
    }
    return url
}
