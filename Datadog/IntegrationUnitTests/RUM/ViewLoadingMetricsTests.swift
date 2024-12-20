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
        rumTime.now.addTimeInterval(TimeBasedTTNSResourcePredicate.defaultThreshold * 0.99) // Wait no more than threshold, so next resource is still counted
        monitor.startResource(resourceKey: "resource3", url: .mockRandom())

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResourceWithError(resourceKey: "resource3", error: ErrorMock(), response: nil)

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
        rumTime.now.addTimeInterval(TimeBasedTTNSResourcePredicate.defaultThreshold * 1.01) // Wait more than threshold, so next resource is not counted
        monitor.startResource(resourceKey: "resource3", url: .mockRandom())

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResourceWithError(resourceKey: "resource2", error: ErrorMock(), response: nil)
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

    func testWhenResourceIsDropped_thenItIsExcludedFromTTNSMetric() throws {
        let droppedResourceURL: URL = .mockRandom()

        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.resourceEventMapper = { event in // drop resource events
            event.resource.url == droppedResourceURL.absoluteString ? nil : event
        }
        rumConfig.errorEventMapper = { event in // drop resource error events
            event.error.resource?.url == droppedResourceURL.absoluteString ? nil : event
        }

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: droppedResourceURL)
        monitor.startResource(resourceKey: "resource3", url: droppedResourceURL)

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        let resource1EndTime = rumTime.now
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResourceWithError(resourceKey: "resource3", error: ErrorMock(), response: nil)

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let lastViewEvent = try XCTUnwrap(session.views.last?.viewEvents.last)
        let actualTTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TTNS should be reported after initial resources end.")
        let expectedTTNS = resource1EndTime.timeIntervalSince(viewStartTime).toInt64Nanoseconds
        XCTAssertEqual(actualTTNS, expectedTTNS, "TTNS should only reflect ACCEPTED resources.")
    }

    // MARK: - Interaction To Next View

    func testWhenActionOccursInPreviousView_andNextViewStarts_thenITNVIsTrackedForNextView() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view is started within the ITNV threshold after the action)
        let expectedITNV: TimeInterval = .mockRandom(min: 0, max: ITNVMetric.Constants.maxDuration * 0.99)
        rumTime.now += expectedITNV
        monitor.startView(key: "next", name: "NextView")

        // Then (ITNV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualITNV = try XCTUnwrap(nextViewEvent.view.interactionToNextViewTime)
        XCTAssertEqual(TimeInterval(fromNanoseconds: actualITNV), expectedITNV, accuracy: 0.01)
    }

    func testWhenActionOccursInPreviousView_andNextViewStartsAfterThreshold_thenITNVIsNotTrackedForNextView() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view starts after exceeding the ITNV threshold)
        rumTime.now += ITNVMetric.Constants.maxDuration + 0.01 // exceeds the max threshold
        monitor.startView(key: "next", name: "NextView")

        // Then (ITNV is not tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualITNV = nextViewEvent.view.interactionToNextViewTime
        XCTAssertNil(actualITNV, "The ITNV value should not be tracked when the next view starts after exceeding the threshold.")
    }

    func testWhenMultipleActionsOccursInPreviousView_thenITNVIsMeasuredFromTheLastAction() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (multiple actions occur in the previous view)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 0.5.seconds
        monitor.addAction(type: .tap, name: "Tap 1")
        rumTime.now += 2.1.seconds
        monitor.addAction(type: .tap, name: "Tap 2")
        rumTime.now += 3.seconds
        monitor.startAction(type: .swipe, name: "Swipe")
        rumTime.now += 0.75.seconds
        monitor.stopAction(type: .swipe, name: "Swipe")

        // When (the next view is started within the ITNV threshold after last action)
        let expectedITNV: TimeInterval = .mockRandom(min: 0, max: ITNVMetric.Constants.maxDuration * 0.99)
        rumTime.now += expectedITNV
        monitor.startView(key: "next", name: "NextView")

        // Then (ITNV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualITNV = try XCTUnwrap(nextViewEvent.view.interactionToNextViewTime)
        XCTAssertEqual(TimeInterval(fromNanoseconds: actualITNV), expectedITNV, accuracy: 0.01)
    }

    func testWhenActionInPreviousViewIsDropped_thenITNVIsNotTracked() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.actionEventMapper = { event in
            event.action.target?.name == "Tap in Previous View" ? nil : event // drop "Tap in Previous View"
        }

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view - which will be dropped)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view is started within the ITNV threshold after the action)
        rumTime.now += ITNVMetric.Constants.maxDuration * 0.5
        monitor.startView(key: "next", name: "NextView")

        // Then (ITNV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        XCTAssertNil(nextViewEvent.view.interactionToNextViewTime, "The ITNV value should not be tracked when the action is dropped.")
    }

    func testITNVIsOnlyTrackedForViewsThatWereStartedDueToAnAction() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (start the previous view and add an action)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view starts due to the action)
        rumTime.now += ITNVMetric.Constants.maxDuration * 0.5
        monitor.startView(key: "next", name: "NextView")

        // When (a new view starts without an action)
        rumTime.now += ITNVMetric.Constants.maxDuration * 0.5
        monitor.startView(key: "nextWithoutAction", name: "NextViewWithoutAction")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let nextViewWithoutAction = try XCTUnwrap(session.views.first(where: { $0.name == "NextViewWithoutAction" })?.viewEvents.last)
        XCTAssertNotNil(nextViewEvent.view.interactionToNextViewTime, "ITNV should be tracked for view that started due to an action.")
        XCTAssertNil(nextViewWithoutAction.view.interactionToNextViewTime, "ITNV should not be tracked for view that started without an action.")
    }
}
