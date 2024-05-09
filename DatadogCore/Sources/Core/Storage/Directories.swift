/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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

    /// Obtains subdirectories for managing batch files for given Feature  (creates if don't exist).
    ///
    /// - Parameter name: The given Feature name.
    /// - Returns: The Feature's directories
    func getFeatureDirectories(forFeatureNamed name: String) throws -> FeatureDirectories {
        return FeatureDirectories(
            unauthorized: try coreDirectory.createSubdirectory(path: "\(name)/intermediate-v2"),
            authorized: try coreDirectory.createSubdirectory(path: "\(name)/v2")
        )
    }
}

internal extension CoreDirectory {
    /// Creates the core directory.
    /// 
    /// - Parameters:
    ///   - osDirectory: the root OS directory (`/Library/Caches`) to create core directory inside.
    ///   - instanceName: The core instance name.
    ///   - site: The cor instance site.
    init(in osDirectory: Directory, instanceName: String, site: DatadogSite) throws {
        let sdkInstanceUUID = sha256("\(instanceName)\(site)")
        let path = "com.datadoghq/v2/\(sdkInstanceUUID)"

        self.init(
            osDirectory: osDirectory,
            coreDirectory: try osDirectory.createSubdirectory(path: path)
        )
    }
}

/// Bundles directories for managing data in single Feature.
internal struct FeatureDirectories {
    /// Data directory for storing unauthorized data collected without knowing the tracking consent value.
    /// Due to the consent change, data in this directory may be either moved to `authorized` folder or entirely deleted.
    let unauthorized: Directory
    /// Data directory for storing authorized data collected when tracking consent is granted.
    /// Consent change does not impact data already stored in this folder.
    /// Data in this folder gets uploaded to the server.
    let authorized: Directory
}
