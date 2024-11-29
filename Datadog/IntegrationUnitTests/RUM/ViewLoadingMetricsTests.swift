/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class ViewLoadingMetricsTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
        rumConfig = RUM.Configuration(applicationID: .mockAny())
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    // MARK: - Time To Network Settled

    func testWhenResourcesStartBeforeThreshold_thenTheyAreIncludedInTTNSMetric() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())
        rumTime.now.addTimeInterval(TTNSMetric.Constants.initialResourceThreshold * 0.99) // Wait no more than threshold, so next resource is still counted
        monitor.startResource(resourceKey: "resource3", url: .mockRandom())

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource3", response: .mockAny())

        // Then
        let lastResourceTime = rumTime.now
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let lastViewEvent = try XCTUnwrap(session.views.last?.viewEvents.last)
        let actualTTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TTNS should be reported after initial resources complete loading.")
        let expectedTTNS = lastResourceTime.timeIntervalSince(viewStartTime).toInt64Nanoseconds
        XCTAssertEqual(actualTTNS, expectedTTNS, "TTNS should span from the view start to the last completed initial resource.")
    }

    func testWhenAnotherResourceStartsAfterThreshold_thenItIsNotIncludedInTTNSMetric() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())

        // When (start non-initial resource after threshold)
        rumTime.now.addTimeInterval(TTNSMetric.Constants.initialResourceThreshold * 1.01) // Wait more than threshold, so next resource is not counted
        monitor.startResource(resourceKey: "resource3", url: .mockRandom())

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        let lastInitialResourceTime = rumTime.now
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource3", response: .mockAny())

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let lastViewEvent = try XCTUnwrap(session.views.last?.viewEvents.last)
        let actualTTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TTNS should be reported after initial resources complete loading.")
        let expectedTTNS = lastInitialResourceTime.timeIntervalSince(viewStartTime).toInt64Nanoseconds
        XCTAssertEqual(actualTTNS, expectedTTNS, "TTNS should span from the view start to the last completed initial resource.")
    }

    func testWhenViewIsStopped_thenTTNSIsNotReported() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (start view and resources)
        monitor.startView(key: "view1", name: "FirstView")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())
        monitor.startResource(resourceKey: "resource3", url: .mockRandom())

        // When (end some resource during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())

        // When (start another view before other resources end)
        monitor.startView(key: "view2", name: "SecondView")
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource3", response: .mockAny())

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let firstView = try XCTUnwrap(session.views.first(where: { $0.name == "FirstView" }))
        let lastViewEvent = try XCTUnwrap(firstView.viewEvents.last)
        XCTAssertNil(lastViewEvent.view.networkSettledTime, "TTNS should not be reported if view was stopped during resource loading.")
    }
}
