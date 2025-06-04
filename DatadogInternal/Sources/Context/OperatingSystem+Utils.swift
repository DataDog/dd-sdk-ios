/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension OperatingSystem {
    /// Creates operating system info.
    ///
    /// - Parameters:
    ///   - name: Operating system name, e.g. Android, iOS
    ///   - version: Full operating system version, e.g. 8.1.1
    ///   - build: Operating system build number, e.g. 15D21
    public init(
        name: String,
        version: String,
        build: String?
    ) {
        self.name = name
        self.version = version
        self.versionMajor = version.split(separator: ".").first.map { String($0) } ?? version
        self.build = build
    }

#if canImport(UIKit)
    /// Creates operating system info based on device description.
    ///
    /// - Parameters:
    ///   - device: The device description.
    ///   - sysctl: Utilities around the `Darwin.sysctl` function.
    public init(
        device: _UIDevice = .dd.current,
        sysctl: SysctlProviding = Sysctl()
    ) {
        let build = try? sysctl.osBuild()

        self.init(
            name: device.systemName,
            version: device.systemVersion,
            build: build
        )
    }
#elseif os(macOS)
    /// Creates operating system info based on process information.
    ///
    /// - Parameters:
    ///   - processInfo: The current process information.
    ///   - sysctl: Utilities around the `Darwin.sysctl` function.
    public init(
        processInfo: ProcessInfo = .processInfo,
        sysctl: SysctlProviding = Sysctl()
    ) {
        let systemVersion = processInfo.operatingSystemVersion
        let build = (try? sysctl.osBuild()) ?? ""

        self.init(
            name: "macOS",
            version: "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)",
            build: build
        )
    }
#endif
}
