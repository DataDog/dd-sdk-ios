/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import Foundation
import KSCrashRecording

internal final class ProbeCrashReporter {
    private let crash = KSCrash.shared
    private let directory: URL
    private(set) var installed = false
    private(set) var evidence = ProbeReporterEvidence()

    init(directory: URL, runID: String, previousID: String?) {
        self.directory = directory
        let root = directory.appendingPathComponent("CrashReporter", isDirectory: true)
        let config = KSCrashConfiguration()
        config.installPath = root.path
        // Same version and monitors as Datadog's KSCrashPlugin. No sink or network SDK is initialized.
        config.monitors = [.signal, .cppException, .nsException, .system]
        config.enableSwapCxaThrow = false
        config.reportStoreConfiguration.maxReportCount = 1
        config.reportStoreConfiguration.reportCleanupPolicy = .never
        config.userInfoJSON = ["probe_run_id": runID]
        do {
            try crash.install(with: config)
            guard let reports = crash.reportStore else { throw ProbeStoreError.ioFailure }
            installed = true
            evidence.crashedLastLaunch = crash.crashedLastLaunch
            let path = root.appendingPathComponent(CrashReportStore.defaultInstallSubfolder, isDirectory: true)
            evidence = try read(at: path, previousID: previousID)
            // Preserve strict raw JSON before removing pending reports, as the SDK normally does.
            if evidence.read == .empty || evidence.read == .capturedCrash {
                reports.deleteAllReports()
            }
        } catch {
            evidence.read = installed ? .readFailed : .installFailed
            evidence.failure = String(describing: type(of: error))
        }
    }

    private func read(at path: URL, previousID: String?) throws -> ProbeReporterEvidence {
        var result = ProbeReporterEvidence(read: .empty, crashedLastLaunch: crash.crashedLastLaunch)
        // Throwing enumeration distinguishes an unavailable directory from an empty report list.
        let files = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard file.pathExtension == "json" else { throw ProbeStoreError.ioFailure }
            let data = try Data(contentsOf: file)
            let archive = "crash-report-\(UUID().uuidString).json"
            try ProbeStore(directory: directory).atomic(data, to: directory.appendingPathComponent(archive))
            result.archivedReports.append(archive)
            guard let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let user = report["user"] as? [String: Any],
                let runID = user["probe_run_id"] as? String,
                let crash = report["crash"] as? [String: Any], crash["error"] != nil
            else {
                result.read = .unmatchedReport
                continue
            }
            result.reportRunIDs.append(runID)
            if runID != previousID {
                result.read = .unmatchedReport
            } else if result.read != .unmatchedReport {
                result.read = .capturedCrash
            }
        }
        if result.crashedLastLaunch == true && result.read == .empty { result.read = .readFailed }
        return result
    }

    // Exercise the real throwing reader against a file where a directory is required. The live
    // reporter directory and its reports remain intact. This is a diagnostic fixture, not an OS exit.
    func verifyReadRefusal() -> ProbeReporterEvidence {
        let fixture = directory.appendingPathComponent("reporter-read-failure-fixture")
        do {
            try ProbeStore(directory: directory).atomic(Data("not a directory".utf8), to: fixture)
            _ = try read(at: fixture, previousID: nil)
            return ProbeReporterEvidence(read: .unavailable, failure: "failure_fixture_unexpectedly_readable")
        } catch {
            return ProbeReporterEvidence(
                read: .readFailed,
                crashedLastLaunch: evidence.crashedLastLaunch,
                failure: "directory_read_failure_fixture"
            )
        }
    }
}
