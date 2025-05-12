/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

public protocol DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier
    func actionModifier(name: String) -> AnyViewModifier
}

struct NOPDatadogMonitor: DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
    func actionModifier(name: String) -> AnyViewModifier { AnyViewModifier() }
}
