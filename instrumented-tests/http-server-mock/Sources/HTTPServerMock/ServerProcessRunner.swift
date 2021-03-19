/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides url to running mock server.
public struct ServerProcess {
    public let serverURL: URL
}

/// Helper type to obtain url of a running mock server.
public class ServerProcessRunner {
    private let serverURL: URL

    public init(serverURL: URL) {
        self.serverURL = serverURL
    }

    /// Waits until server is reachable.
    /// Returns `ServerProcess` instance if the server is running, `nil` otherwise.
    public func waitUntilServerIsReachable() -> ServerProcess? {
        let deadline = Date(timeIntervalSinceNow: 5)

        while Date() < deadline {
            if ping() {
                return ServerProcess(serverURL: serverURL)
            }
        }

        return nil
    }

    private func ping() -> Bool {
        let knownEndpointURL = serverURL.appendingPathComponent("/inspect")
        return (try? Data(contentsOf: knownEndpointURL)) != nil
    }
}
