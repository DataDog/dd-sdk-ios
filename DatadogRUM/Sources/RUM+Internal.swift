/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2023-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUM: InternalExtended {}

extension InternalExtension where ExtendedType == RUM {
    /// Check whether `RUM` has been enabled for a specific SDK instance.
    ///
    /// - Parameters:
    ///    - in: the core to check
    ///
    /// - Returns: true if `RUM` has been enabled for the supplied core.
    public static func isEnabled(in core: DatadogCoreProtocol = CoreRegistry.default) -> Bool {
        return core.get(feature: RUMFeature.self) != nil
    }
}
