/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

public protocol AnyMockable {
    static func mockAny() -> Self
}

public protocol RandomMockable {
    static func mockRandom() -> Self
}
