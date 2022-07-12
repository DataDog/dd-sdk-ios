/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

import XCTest
@testable import Datadog

class InternalProxyTests: XCTestCase {
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
        let v1Context = try XCTUnwrap(core.v1.context, "`DatadogCore` must be initialized before creating `RUMMonitor`")
        return RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                rumFeature: rumFeature,
                crashReportingFeature: crashReportingFeature,
                context: v1Context
            ).replacing(viewUpdatesThrottlerFactory: { NoOpRUMViewUpdatesThrottler() }),
            dateProvider: v1Context.dateProvider
        )
    }

    func testProxyDebugCallsTelemetryDebug() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        let id: String = .mockAny()
        let message: String = .mockAny()

        // When
        Datadog._internal._telemtry.debug(id: id, message: message)

        // Then
        XCTAssertEqual(dd.telemetry.debugs.count, 1)
        XCTAssertEqual(dd.telemetry.debugs.first, message)
    }

    func testProxyErrorCallsTelemetryError() {
        // Given
        let dd = DD.mockWith(telemetry: TelemetryMock())
        defer { dd.reset() }

        let id: String = .mockAny()
        let message: String = .mockAny()
        let stack: String = .mockAny()
        let kind: String = .mockAny()

        // When
        Datadog._internal._telemtry.error(id: id, message: message, kind: kind, stack: stack)

        // Then
        XCTAssertEqual(dd.telemetry.errors.count, 1)
        let error = dd.telemetry.errors.first
        XCTAssertEqual(error?.message, message)
        XCTAssertEqual(error?.kind, kind)
        XCTAssertEqual(error?.stack, stack)
    }

    func testProxyAddLongTaskCallsRumMonitor() throws {
        // Given
        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        let duration: TimeInterval = .mockRandom()
        let internalProxy = _InternalProxy(monitor: monitor as? RUMMonitor)

        // When
        monitor.startView(viewController: mockView)
        internalProxy._rum?.addLongTask(at: Date(), duration: duration)

        let rumEventMatchers = try rum.waitAndReturnRUMEventMatchers(count: 3)

        // Then
        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let longTask = session.viewVisits[0].longTaskEvents.first
        XCTAssertEqual(longTask?.longTask.duration, duration.toInt64Nanoseconds)
    }
}
