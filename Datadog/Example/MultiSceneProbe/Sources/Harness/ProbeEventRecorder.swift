/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class ProbeEventRecorder: @unchecked Sendable {
    typealias Sink = @Sendable (String) -> Void
    typealias Clock = @Sendable () -> Int64

    private let runID: String
    private let scenarioID: String
    private let sink: Sink
    private let clock: Clock
    private let lock = NSLock()
    private var nextSequence: UInt64 = 1
    private var signals: [ProbeSignal] = []

    init(
        runID: String,
        scenarioID: String,
        sink: @escaping Sink = { print("🔬 [RUM Native Multi-Scene JSONL] \($0)") },
        clock: @escaping Clock = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        self.runID = runID
        self.scenarioID = scenarioID
        self.sink = sink
        self.clock = clock
    }

    @discardableResult
    func record(_ draft: ProbeSignal) -> ProbeSignal {
        lock.lock()
        defer { lock.unlock() }

        let signal = draft.enveloped(
            sequence: nextSequence,
            timestampMilliseconds: clock(),
            runID: runID,
            scenarioID: scenarioID
        )
        nextSequence &+= 1
        signals.append(signal)
        sink(encode(signal))
        return signal
    }

    func snapshot() -> [ProbeSignal] {
        lock.lock()
        defer { lock.unlock() }
        return signals
    }

    private func encode(_ signal: ProbeSignal) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(ProbeSignalRecord(signal: signal)),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"type":"signal-encoding-failed"}"#
        }
        return json
    }
}
