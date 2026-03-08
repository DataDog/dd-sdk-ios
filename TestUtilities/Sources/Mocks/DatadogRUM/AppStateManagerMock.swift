/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
@testable import DatadogRUM

/// Mock of the AppState manager.
public final class AppStateManagerMock: AppStateManaging, @unchecked Sendable {
    public var _previousAppStateInfo: AppStateInfo?
    public var _currentAppStateInfo: AppStateInfo = .mockAny()

    public init() {}

    public func deleteAppState() {}
    public func updateAppState(state: AppState) async {}
    public func fetchAppStateInfo() async -> (previous: AppStateInfo?, current: AppStateInfo) {
        (_previousAppStateInfo, _currentAppStateInfo)
    }
    public func storeCurrentAppState() {}
}
