/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal
@testable import DatadogRUM

/// Mock of the AppState manager.
public final class AppStateManagerMock: AppStateManaging {
    public var previousAppStateInfo: AppStateInfo?
    public var currentAppStateInfo: AppStateInfo? = .mockAny()

    public func deleteAppState() {}
    public func updateAppState(state: AppState) {}
    public func currentAppStateInfo(completion: @escaping (AppStateInfo) -> Void) throws {
        guard let currentAppStateInfo else {
            throw ErrorMock()
        }
        completion(currentAppStateInfo)
    }
    public func storeCurrentAppState() throws {}
}
