/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension Thread: DatadogExtended {}
extension DatadogExtension where ExtendedType: Thread {
    /// Returns the name of current thread if available or the nature of thread otherwise: `"main" | "background"`.
    public var name: String {
        if let name = Thread.current.name, !name.isEmpty {
            return name
        }

        return Thread.isMainThread ? "main" : "background"
    }
}
