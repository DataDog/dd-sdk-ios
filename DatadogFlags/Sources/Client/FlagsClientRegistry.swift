/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class FlagsClientRegistry {
    @ReadWriteLock
    private var clients: [String: FlagsClientProtocol] = [:]

    func register(_ client: FlagsClientProtocol, named name: String) {
        guard !isRegistered(clientName: name) else {
            DD.logger.warn("A flags client with name \(name) has already been registered.")
            return
        }
        clients[name] = client
    }

    func isRegistered(clientName: String) -> Bool {
        clients[clientName] != nil
    }

    @discardableResult
    func unregisterClient(named name: String) -> FlagsClientProtocol? {
        clients.removeValue(forKey: name)
    }

    func client(named name: String) -> FlagsClientProtocol {
        clients[name] ?? NOPFlagsClient()
    }
}
