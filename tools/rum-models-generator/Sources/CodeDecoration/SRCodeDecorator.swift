/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CodeGeneration

/// Adjusts naming and structure of generated code for Session Replay.
public class SRCodeDecorator: CodeDecorator {
    public init() {}

    // MARK: - CodeDecorator

    public func decorate(code: GeneratedCode) throws -> GeneratedCode {
        return code // RUMM-2266 Implement actual decoration
    }
}
