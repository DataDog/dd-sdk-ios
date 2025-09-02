/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Datadog assertion helper.
///
/// - Ensures assumptions that should **never** be violated.
/// - **Fails only in development** to catch mistakes early.
/// - **Never** crashes customer apps in production, even if they enable assertions in Release builds.
///
/// ## Why it fails only in development?
/// - This function uses `assert()`, which is **completely removed** in Release builds by default.
/// - Some apps may opt into assertions in Release using `-Xfrontend -enable-assertions`, but this function explicitly restricts assertions to **Debug** builds only.
/// - In production, the check is stripped out, ensuring zero impact on customer apps.
@inline(__always)
public func dd_assert(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    line: UInt = #line
) {
    #if DEBUG
    assert(condition(), message(), file: file, line: line)
    #endif
}
