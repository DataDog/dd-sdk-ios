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
    private let lock = NSRecursiveLock()
    private var nextSequence: UInt64 = 1
    private var signals: [ProbeSignal] = []
    private var signalContinuations: [
        UUID: AsyncStream<ProbeSignal>.Continuation
    ] = [:]
    private var terminalResult: ProbeSemanticResult?

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
        signalContinuations.values.forEach { $0.yield(signal) }
        return signal
    }

    func snapshot() -> [ProbeSignal] {
        lock.lock()
        defer { lock.unlock() }
        return signals
    }

    func signalStream() -> AsyncStream<ProbeSignal> {
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(4_096)) { continuation in
            lock.lock()
            signals.forEach { continuation.yield($0) }
            signalContinuations[identifier] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeSignalContinuation(identifier)
            }
        }
    }

    @discardableResult
    func recordTerminalResult(_ result: ProbeSemanticResult) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard terminalResult == nil else {
            return false
        }
        terminalResult = result
        sink(encode(result))
        return true
    }

    func recordedTerminalResult() -> ProbeSemanticResult? {
        lock.lock()
        defer { lock.unlock() }
        return terminalResult
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

    private func encode(_ result: ProbeSemanticResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(
                ProbeSemanticResultRecord(runID: runID, result: result)
            ),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"type":"semantic-result-encoding-failed"}"#
        }
        return json
    }

    private func removeSignalContinuation(_ identifier: UUID) {
        lock.lock()
        defer { lock.unlock() }
        signalContinuations.removeValue(forKey: identifier)
    }
}
