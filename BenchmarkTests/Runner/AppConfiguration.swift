/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogCore

/// Application info reads configuration from `Info.plist`.
///
/// The expected format is as follow:
///
///     <dict>
///         <key>DatadogConfiguration</key>
///         <dict>
///             <key>ClientToken</key>
///             <string>$(CLIENT_TOKEN)</string>
///             <key>ApplicationID</key>
///             <string>$(RUM_APPLICATION_ID)</string>
///             <key>ApiKey</key>
///             <string>$(API_KEY)</string>
///             <key>Environment</key>
///             <string>$(DD_ENV)</string>
///             <key>Site</key>
///             <string>$(DD_SITE)</string>
///         </dict>
///     </dict>
struct AppInfo {
    let clientToken: String
    let applicationID: String
    let apiKey: String
    let site: DatadogSite
    let env: String
}

extension AppInfo {
    init(bundle: Bundle = .main) throws {
        guard
            let obj = bundle.object(forInfoDictionaryKey: "DatadogConfiguration") as? [String: String],
            let clientToken = obj["ClientToken"],
            let applicationID = obj["ApplicationID"],
            let apiKey = obj["ApiKey"],
            let site = obj["Site"].flatMap(DatadogSite.init(rawValue:)),
            let env = obj["Environment"]
        else {
            throw ProgrammerError(description: "Missing required Info.plist keys")
        }

        self = .init(
            clientToken: clientToken,
            applicationID: applicationID,
            apiKey: apiKey,
            site: site,
            env: env
        )
    }
}

extension AppInfo {
    static var empty: Self {
        .init(
            clientToken: "",
            applicationID: "",
            apiKey: "",
            site: .us1,
            env: "benchmarks"
        )
    }
}

extension Datadog.Configuration {
    static func benchmark(info: AppInfo) -> Self {
        .init(
            clientToken: info.clientToken,
            env: info.env,
            site: info.site,
            service: "ios-benchmark"
        )
    }
}
