/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// Temporary forward declaration to resolve compilation order issues
public struct FlagsConfiguration {
    public init() {}
}

public enum Flags {
    public static func enable(with configuration: FlagsConfiguration) {
        // TODO: RUM-000 (for the linter, actually FFL-1015) Initialize flags feature
    }
}
