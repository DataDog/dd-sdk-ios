/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
class SwiftUINavigationOwnershipTests: XCTestCase {
    // Each test owns a unique directory; simultaneous Core instances use separate directories below.
    var temporaryCoreDirectory: CoreDirectory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryCoreDirectory = temporaryUniqueCoreDirectory()
        try temporaryCoreDirectory.create()
    }

    override func tearDownWithError() throws {
        defer {
            temporaryCoreDirectory = nil
        }
        if let directory = temporaryCoreDirectory {
            try directory.delete()
        }
        try super.tearDownWithError()
    }

    func makeHandoffCore() -> DatadogCore {
        DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
    }

    @MainActor
    func makeOwnedSwiftUIFeature(in core: DatadogCore) throws -> RUMFeature {
        let date = Date()
        core.contextProvider.write { context in
            context = .mockWith(
                sdkInitDate: date,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date),
                applicationStateHistory: .mockWith(initialState: .active, date: date)
            )
        }
        core.flush()
        var configuration = RUM.Configuration(applicationID: "owned-swiftui", trackAnonymousUser: false)
        configuration.bundle = .mockWith(UIApplicationSceneManifest: ["UIApplicationSupportsMultipleScenes": true])
        configuration.featureFlags = [.multiSceneTracking: true]
        configuration.sessionSampleRate = 100
        configuration.vitalsUpdateFrequency = nil
        try RUM.enableOrThrow(with: configuration, in: core)
        core.flush()
        return try XCTUnwrap(core.get(feature: RUMFeature.self))
    }
}
#endif
