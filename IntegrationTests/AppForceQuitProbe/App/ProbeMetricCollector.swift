/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation
import MetricKit

internal struct ProbeDiagnostic: Codable {
    var kind: String
    var received: ProbeStamp
    var processID: Int32?
    var begin: Double?
    var end: Double?
    var archivedFile: String?
    var error: String?
}

@available(iOS 27.0, *)
@MainActor
internal final class ProbeMetricCollector {
    private let manager = MetricManager()
    private var task: Task<Void, Never>?

    init(directory: URL, received: @escaping (ProbeDiagnostic) -> Void) {
        task = Task { [manager] in
            for await report in manager.diagnosticReports {
                let kind: String
                switch report.result {
                case .memoryException: kind = "memory_exception"
                case .crash: kind = "crash"
                case .hang: kind = "hang"
                default: kind = "other"
                }
                var diagnostic = ProbeDiagnostic(
                    kind: kind,
                    received: ProbeCapture.stamp(),
                    processID: report.environment.pid,
                    begin: report.timeRange.start.timeIntervalSince1970,
                    end: report.timeRange.end.timeIntervalSince1970
                )
                do {
                    let name = "metrickit-\(UUID().uuidString).json"
                    try ProbeStore(directory: directory).atomic(
                        try JSONEncoder().encode(report),
                        to: directory.appendingPathComponent(name)
                    )
                    diagnostic.archivedFile = name
                } catch {
                    diagnostic.error = String(describing: type(of: error))
                }
                // Passive evidence only. Lack of a diagnostic is never a clean-exit assertion.
                received(diagnostic)
            }
        }
    }

    deinit { task?.cancel() }
}
