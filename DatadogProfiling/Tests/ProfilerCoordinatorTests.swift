/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import TestUtilities
@testable import DatadogProfiling

final class ProfilerCoordinatorTests: XCTestCase {
    private var coordinator: ProfilerCoordinator! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        coordinator = ProfilerCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    func testRegistration_assignsCoordinatorToFirstProfilerAndObserverToLaterProfiler() {
        // Given
        let first = profiler()
        let second = profiler()

        // Then
        XCTAssertEqual(first.role, .coordinator)
        XCTAssertEqual(second.role, .observer)
    }

    func testRegistration_assignsCoordinatorAfterPreviousCoordinatorDeallocates() {
        // Given
        var first: DatadogProfiler? = profiler()
        XCTAssertEqual(first?.role, .coordinator)

        // When
        first = nil
        let second = profiler()

        // Then
        XCTAssertEqual(second.role, .coordinator)
    }

    func testRegistration_isThreadSafe() {
        // Given
        let iterations = 100
        var profilers: [DatadogProfiler] = []
        let lock = NSLock()

        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let instance = profiler()
            lock.lock()
            profilers.append(instance)
            lock.unlock()
        }

        // Then
        XCTAssertEqual(profilers.filter { $0.role == .coordinator }.count, 1)
        XCTAssertEqual(profilers.filter { $0.role == .observer }.count, iterations - 1)
    }

    private func profiler() -> DatadogProfiler {
        DatadogProfiler(
            core: PassthroughCoreMock(),
            profilingSamplerProvider: ProfilingSamplerProvider(continuousSampleRate: 0),
            quotaChecker: ProfilingQuotaCheckerMock(),
            profilerCoordinator: self.coordinator
        )
    }
}

#endif
