/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Swift abstraction over compiler flags set in `Active Compilation Conditions` build setting for `Datadog` target.
internal struct CompilationConditions {
    #if DD_SDK_DEVELOPMENT
    /// `true` if `DD_SDK_DEVELOPMENT` flag is set.
    static var isSDKCompiledForDevelopment: Bool = true
    #else
    /// `false` if `DD_SDK_DEVELOPMENT` flag is not set.
    static var isSDKCompiledForDevelopment: Bool = false
    #endif
}
