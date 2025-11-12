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
    private let kscrash: KSCrash

    init(_ kscrash: KSCrash = .shared) throws {
        try kscrash.install(with: .datadog())
        kscrash.reportStore?.sink = CrashReportFilterPipeline(
            filters: [
                DatadogTypeSafeFilter(),
                DatadogMinifyFilter()
            ]
        )

        self.kscrash = kscrash
    }

    // MARK: - CrashReportingPlugin

    func readPendingCrashReport(completion: @escaping (DDCrashReport?) -> Bool) {
        /* no-op */
    }

    func inject(context: Data) {
        /* no-op */
    }

    var backtraceReporter: BacktraceReporting? {
        /* no-op */
        return nil
    }
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
        config.reportStoreConfiguration.maxReportCount = 1
        config.reportStoreConfiguration.reportCleanupPolicy = .never
        return config
    }
}
