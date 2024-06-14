/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct RUMUUID: Equatable, Hashable {
    let rawValue: UUID

    /// UUID with all zeros, used to represent no-op values.
    static let nullUUID = RUMUUID(rawValue: .nullUUID)
}

extension Optional where Wrapped == RUMUUID {
    var orNull: RUMUUID { self ?? RUMUUID.nullUUID }
}
