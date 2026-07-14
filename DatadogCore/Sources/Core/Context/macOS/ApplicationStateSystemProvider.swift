/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)

import AppKit

internal protocol ApplicationStateSystemProvider {
    var isActive: Bool { get }
    var isHidden: Bool { get }
}

internal struct DefaultApplicationStateSystemProvider: ApplicationStateSystemProvider {
    var isActive: Bool {
        NSApplication.shared.isActive
    }

    var isHidden: Bool {
        NSApplication.shared.isHidden
    }
}

#endif
