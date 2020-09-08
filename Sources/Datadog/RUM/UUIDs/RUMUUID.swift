/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct RUMUUID: Equatable {
    let rawValue: UUID

    /// UUID with all zeros, used to represent no-op values.
    static let nullUUID = RUMUUID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID())
}

extension Optional where Wrapped == RUMUUID {
    var orNull: RUMUUID { self ?? RUMUUID.nullUUID }
}
