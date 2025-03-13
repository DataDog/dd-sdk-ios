/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

// MARK: - TopLevelReflector
/// Protocol defining an interface for reflection-based object inspection.
/// `TopLevelReflector` provides a consistent way to navigate through object structures
/// by traversing paths of properties.
internal protocol TopLevelReflector {
    /// Attempts to find a descendant at the specified path.
    func descendant(_ paths: [ReflectionMirror.Path]) -> Any?
}

// MARK: - Reflector
extension Reflector: TopLevelReflector {}
