/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal class E2EConfig {
    private struct InfoPlistKey {
        static let clientToken      = "E2EDatadogClientToken"
        static let rumApplicationID = "E2ERUMApplicationID"
        static let isRunningOnCI    = "IsRunningOnCI"
    }

    private static var bundle: Bundle { Bundle(for: E2EConfig.self) }

    // MARK: - Info.plist

    /// Reads Datadog client token authorizing data for 'Mobile - Instrumentation' org.
    static func readClientToken() -> String {
        guard let clientToken = bundle.infoDictionary?[InfoPlistKey.clientToken] as? String, !clientToken.isEmpty else {
            fatalError(
                """
                ✋⛔️ Cannot read `\(InfoPlistKey.clientToken)` from `Info.plist` dictionary.
                Update `xcconfigs/Datadog.xcconfig` with your own client token obtained on datadoghq.com.
                You might need to run `Product > Clean Build Folder` before retrying.
                """
            )
        }
        return clientToken
    }

    /// Reads RUM Application ID authorizing data for 'Mobile - Instrumentation' org.
    static func readRUMApplicationID() -> String {
        guard let rumApplicationID = bundle.infoDictionary?[InfoPlistKey.rumApplicationID] as? String, !rumApplicationID.isEmpty else {
            fatalError(
                """
                ✋⛔️ Cannot read `\(InfoPlistKey.rumApplicationID)` from `Info.plist` dictionary.
                Update `xcconfigs/Datadog.xcconfig` with your own RUM application id obtained on datadoghq.com.
                You might need to run `Product > Clean Build Folder` before retrying.
                """
            )
        }
        return rumApplicationID
    }

    /// Reads Datadog ENV for tagging events. Returns `debug` for local builds and `instrumentation` for CI.
    /// This way local debug data is excluded from monitors installed in 'Mobile - Instrumentation' org.
    static func readEnv() -> String {
        let isCI = bundle.infoDictionary?[InfoPlistKey.isRunningOnCI] as? String
        return isCI == "true" ? "instrumentation" : "debug"
    }

    /// Checks the ENV configuration consistency.
    /// TODO: RUMM-1249 remove this method when we have both manual and instrumented API tests using client token and RUM app ID.
    static func check() {
        _ = readClientToken()
        _ = readRUMApplicationID()
        print("⚙️ Using DD ENV: '\(readEnv())'")
    }
}
