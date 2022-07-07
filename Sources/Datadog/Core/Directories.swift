/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Indicates the main directory for a given instance of the SDK.
/// Each instance of `DatadogCore` creates its own `CoreDirectory` to manage data for registered Features.
/// The core directory is created under `/Library/Caches` and uses a name that identifies the certain instance
/// of the SDK (`<sdk-instance-uuid>`):
///
/// ```
/// /Library/Cache/com.datadoghq/v2/<sdk-instance-uuid>/
/// ```
///
/// Note: System may delete data in `/Library/Cache` to free up disk space which reduces the impact on devices working
/// under heavy space pressure. This is intentional for Datadog SDK to have its data purged when system needs more memory
/// for other apps.
internal struct CoreDirectory {
    /// A known OS location the core directory is created within:`/Library/Cache`.
    let osDirectory: Directory
    /// The core directory specific to this instance of the SDK: `/Library/Cache/com.datadoghq/v2/<sdk-instance-uuid>`.
    let coreDirectory: Directory

    /// Obtains subdirectories for managing Feature data (creates if don't exist).
    /// - Parameter configuration: the storage configuration for given Feature
    func getFeatureDirectories(configuration: FeatureStorageConfiguration) throws -> FeatureDirectories {
        return FeatureDirectories(
            deprecated: configuration.directories.deprecated.compactMap { deprecatedPath in
                try? osDirectory.subdirectory(path: deprecatedPath) // ignore errors - deprecated paths likely do not exist
            },
            unauthorized: try coreDirectory.createSubdirectory(path: configuration.directories.unauthorized),
            authorized: try coreDirectory.createSubdirectory(path: configuration.directories.authorized)
        )
    }
}

internal extension CoreDirectory {
    /// Creates the core directory.
    /// - Parameters:
    ///   - osDirectory: the root OS directory (`/Library/Caches`) to create core directory inside.
    ///   - configuration: the configuration of SDK instance. It is used to determine unique path of the core
    ///   directory created for this instance of the SDK.
    init(in osDirectory: Directory, from configuration: CoreConfiguration) throws {
        let clientToken = configuration.clientToken
        let site = configuration.site?.rawValue ?? ""

        let sdkInstanceUUID = sha256("\(clientToken)\(site)")
        let path = "com.datadoghq/v2/\(sdkInstanceUUID)"

        self.init(
            osDirectory: osDirectory,
            coreDirectory: try osDirectory.createSubdirectory(path: path)
        )
    }
}

/// Bundles directories for managing data in single Feature.
internal struct FeatureDirectories {
    /// Deprecated data directory that can be deleted safely.
    let deprecated: [Directory]
    /// Data directory for storing unauthorized data collected without knowing the tracking consent value.
    /// Due to the consent change, data in this directory may be either moved to `authorized` folder or entirely deleted.
    let unauthorized: Directory
    /// Data directory for storing authorized data collected when tracking consent is granted.
    /// Consent change does not impact data already stored in this folder.
    /// Data in this folder gets uploaded to the server.
    let authorized: Directory
}
