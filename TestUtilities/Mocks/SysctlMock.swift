/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */


import Foundation
import DatadogInternal

public final class SysctlMock: SysctlProviding, RandomMockable {
    public static func mockRandom() -> SysctlMock {
        return .init()
    }

    public var stubbedOSVersion: String = .mockRandom()
    public func osVersion() throws -> String {
        return stubbedOSVersion
    }

    public var stubbedSystemBootTime: TimeInterval = .mockRandom()
    public func systemBootTime() throws -> TimeInterval {
        return stubbedSystemBootTime
    }

    public var stubbedIsDebugging: Bool = .mockRandom()
    public func isDebugging() -> Bool {
        return stubbedIsDebugging
    }
}
