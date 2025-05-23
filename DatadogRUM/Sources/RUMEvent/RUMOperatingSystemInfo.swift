/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUMOperatingSystem {
    init(device: DeviceInfo) {
        self.init(
            build: device.osBuildNumber,
            name: device.osName,
            version: device.osVersion,
            versionMajor: device.osVersionMajor
        )
    }
}
