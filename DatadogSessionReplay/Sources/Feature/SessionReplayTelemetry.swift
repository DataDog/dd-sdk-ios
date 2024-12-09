/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import DatadogInternal

/// Session Replay Telemetry forwards telemetry events on a dedicated queue
/// and deduplicate debug and error messages based on their ids.
internal final class SessionReplayTelemetry {
    private let forward: Telemetry
    private let queue: Queue

    /// Keps hash values of debug/error ids.
    private var hashTable = Set<Int>()

    init(telemetry: Telemetry, queue: Queue) {
        self.forward = telemetry
        self.queue = queue
    }
}

extension SessionReplayTelemetry: Telemetry {
    func send(telemetry: DatadogInternal.TelemetryMessage) {
        queue.run { [weak self] in
            guard let self else {
                return
            }

            switch telemetry {
            case .debug(let id, _, _), .error(let id, _, _, _):
                let hash = id.hashValue

                if self.hashTable.contains(hash) {
                    return
                }

                self.hashTable.insert(hash)
                self.forward.send(telemetry: telemetry)

            default:
                self.forward.send(telemetry: telemetry)
            }
        }
    }
}

#endif
