/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct Environment {
    struct InfoPlistKey {
        static let clientToken      = "DatadogClientToken"
        static let rumApplicationID = "RUMApplicationID"
        static let metricsAPIKey    = "MetricsAPIKey"
        static let benchmarkRunType = "BenchmarkRunType"
    }

    enum BenchmarkRunType: String {
        case baseline = "baseline"
        case instrumented = "instrumented"
    }

    static func readClientToken() -> String {
        guard let clientToken = Bundle.main.infoDictionary?[InfoPlistKey.clientToken] as? String, !clientToken.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `\(InfoPlistKey.clientToken)` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            client token obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }
        return clientToken
    }

    static func readRUMApplicationID() -> String {
        guard let rumApplicationID = Bundle.main.infoDictionary![InfoPlistKey.rumApplicationID] as? String, !rumApplicationID.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `\(InfoPlistKey.rumApplicationID)` from `Info.plist` dictionary.
            Please update `Datadog.xcconfig` in the repository root with your own
            RUM application id obtained on datadoghq.com.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }
        return rumApplicationID
    }

    static func apiKey() -> String {
        guard let apiKey = Bundle.main.infoDictionary![InfoPlistKey.metricsAPIKey] as? String, !apiKey.isEmpty else {
            fatalError("""
            ✋⛔️ Cannot read `\(InfoPlistKey.metricsAPIKey)` from `Info.plist` dictionary.
            You might need to run `Product > Clean Build Folder` before retrying.
            """)
        }
        return apiKey
    }

    static var skipBenchmarkDataUpload: Bool {
        return ProcessInfo.processInfo.environment["SKIP_BENCHMARK_DATA_UPLOAD"] == "1"
    }

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
