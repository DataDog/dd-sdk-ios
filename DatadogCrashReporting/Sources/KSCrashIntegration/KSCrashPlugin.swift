/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
internal import KSCrashFilters
#else
@_implementationOnly import KSCrashRecording
@_implementationOnly import KSCrashFilters
#endif
// swiftlint:enable duplicate_imports

/// The implementation of `CrashReportingPlugin`.
/// Pass its instance as the crash reporting plugin for Datadog SDK to enable crash reporting feature.
@objc
internal class KSCrashPlugin: NSObject, CrashReportingPlugin {
    private let store: CrashReportStore
    private let telemetry: Telemetry

    init(_ kscrash: KSCrash = .shared, telemetry: Telemetry = NOPTelemetry()) throws {
        do {
            try kscrash.install(with: .datadog())
            kscrash.reportStore?.sink = CrashReportFilterPipeline(
                filters: [
                    DatadogTypeSafeFilter(),
                    DatadogMinifyFilter(),
                    DatadogDiagnosticFilter(),
                    DatadogCrashReportFilter()
                ]
            )
            telemetry.debug("[KSCrash] Successfully installed")
        } catch KSCrashInstallError.alreadyInstalled {
            consolePrint("DatadogCrashReporting error: crash reporting is already installed", .warn)
            telemetry.debug("[KSCrash] already installed")
        } catch {
            telemetry.error("[KSCrash] Fails installation", error: error)
            throw error
        }

        guard let store = kscrash.reportStore else {
            throw CrashReportException(description: "[KSCrash] Report store should exist after installation")
        }

        self.telemetry = telemetry
        self.store = store
        super.init()
    }

    // MARK: - CrashReportingPlugin

    func readPendingCrashReport(completion: @escaping (DDCrashReport?) -> Bool) {
        self.store.sendAllReports { reports, error in
            do {
                if let error {
                    throw error
                }

                guard let report = reports?.first else {
                    _ = completion(nil)
                    self.telemetry.debug("[KSCrash] No crash report to load")
                    return
                }

                guard let report = report.untypedValue as? DDCrashReport else {
                    throw CrashReportException(description: "Report is not of type DDCrashReport")
                }

                if completion(report) {
                    self.store.deleteAllReports()
                }

                self.telemetry.debug("[KSCrash] Successfully loaded crash report")
            } catch {
                _ = completion(nil)
                self.store.deleteAllReports()
                consolePrint("🔥 DatadogCrashReporting error: failed to load crash report: \(error)", .error)
                self.telemetry.error("[KSCrash] Fails to load crash report", error: error)
            }
        }
    }

    func inject(context: Data) {
        context.withUnsafeBytes {
            let c_char = $0.bindMemory(to: CChar.self).baseAddress
            kscrash_setUserInfoJSON(c_char)
        }
    }

    var backtraceReporter: BacktraceReporting? { KSCrashBacktrace(telemetry: telemetry) }
}

extension KSCrashConfiguration {
    static func datadog() throws -> KSCrashConfiguration {
        let version = "v2"

        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CrashReportException(description: "Cannot obtain `/Library/Caches/` url.")
        }

        let directory = cache.appendingPathComponent("com.datadoghq.crash-reporting/\(version)", isDirectory: true)

        let config = KSCrashConfiguration()
        config.installPath = directory.path
        // Disable `.mackException` monitor. The choice of `.BSD` (.signal) over `.mach` is well discussed here:
        // https://github.com/microsoft/PLCrashReporter/blob/7f27b272d5ff0d6650fc41317127bb2378ed6e88/Source/CrashReporter.h#L238-L363
        config.monitors = [.signal, .cppException, .nsException, .system]
        config.reportStoreConfiguration.maxReportCount = 1
        config.reportStoreConfiguration.reportCleanupPolicy = .never
        return config
    }
}
