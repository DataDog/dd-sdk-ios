/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

class RUMInternalProxyTests: XCTestCase {
    private var core: DatadogCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreMock()
    }

    override func tearDown() {
        core.flush()
        core = nil
        super.tearDown()
    }

    /// Creates `RUMMonitor` instance for tests.
    /// The only difference vs. `RUMMonitor.initialize()` is that we disable RUM view updates sampling to get deterministic behaviour.
    private func createTestableRUMMonitor() throws -> DDRUMMonitor {
        let rumFeature: RUMFeature = try XCTUnwrap(core.v1.feature(RUMFeature.self), "RUM feature must be initialized before creating `RUMMonitor`")
        let crashReportingFeature = core.v1.feature(CrashReportingFeature.self)
        return RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                rumFeature: rumFeature,
                crashReportingFeature: crashReportingFeature
            ).replacing(viewUpdatesThrottlerFactory: { NoOpRUMViewUpdatesThrottler() }),
            dateProvider: rumFeature.configuration.dateProvider
        )
    }

    func testProxyAddLongTaskSendsLongTasks() throws {
        // Given
        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        let date = Date()
        let duration: TimeInterval = .mockRandom()

        // When
        monitor.startView(viewController: mockView)
        monitor._internal.addLongTask(at: date, duration: duration)

        let rumEventMatchers = try rum.waitAndReturnRUMEventMatchers(count: 3)

        // Then
        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let longTask = session.viewVisits[0].longTaskEvents.first
        XCTAssertEqual(longTask?.date, (date - duration).timeIntervalSince1970.toInt64Nanoseconds)
        XCTAssertEqual(longTask?.longTask.duration, duration.toInt64Nanoseconds)
    }
}
