/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class ViewLoadingMetricsTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
        rumConfig = RUM.Configuration(applicationID: .mockAny())
    }

        override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    // MARK: - Time To Network Settled

    func testWhenResourcesStartBeforeThreshold_thenTheyAreIncludedInTNSMetric() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default TNS resource predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())
        rumTime.now.addTimeInterval(TimeBasedTNSResourcePredicate.defaultThreshold * 0.99) // Wait no more than threshold, so next resource is still counted
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
        let actualTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TNS should be reported after initial resources complete loading.")
        let expectedTNS = lastResourceTime.timeIntervalSince(viewStartTime).dd_toInt64Nanoseconds
        XCTAssertEqual(actualTNS, expectedTNS, "TNS should span from the view start to the last completed initial resource.")
    }

    @available(iOS 13, *)
    func testWhenResourcesHaveMetrics_thenTheyAreIncludedInTNSMetricCalculation() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default TNS resource predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())
        rumTime.now.addTimeInterval(TimeBasedTNSResourcePredicate.defaultThreshold * 0.99) // Wait no more than threshold, so next resource is still counted

        // When (end resources during the same view)
        rumTime.now.addTimeInterval(1)
        let resource1RealDuration: TimeInterval = 5
        let resource1TaskInterval: DateInterval = .init(start: viewStartTime, duration: resource1RealDuration)
        monitor.addResourceMetrics(
            resourceKey: "resource1",
            metrics: .mockWith(taskInterval: resource1TaskInterval),
            attributes: [:]
        )
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        rumTime.now.addTimeInterval(1)
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())

        // Then
        let lastResourceTime = max(resource1TaskInterval.end, rumTime.now)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let lastViewEvent = try XCTUnwrap(session.views.last?.viewEvents.last)
        let actualTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TNS should be reported after initial resources complete loading.")
        let expectedTNS = lastResourceTime.timeIntervalSince(viewStartTime).dd_toInt64Nanoseconds
        XCTAssertEqual(actualTNS, expectedTNS, "TNS should span from the view start to the last completed initial resource (resource1 with correct metrics).")
    }

    func testWhenAnotherResourceStartsAfterThreshold_thenItIsNotIncludedInTNSMetric() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default TNS resource predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view and initial resources)
        monitor.startView(key: "view", name: "ViewName")
        monitor.startResource(resourceKey: "resource1", url: .mockRandom())
        monitor.startResource(resourceKey: "resource2", url: .mockRandom())

        // When (start non-initial resource after threshold)
        rumTime.now.addTimeInterval(TimeBasedTNSResourcePredicate.defaultThreshold * 1.01) // Wait more than threshold, so next resource is not counted
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
        let actualTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TNS should be reported after initial resources complete loading.")
        let expectedTNS = lastInitialResourceTime.timeIntervalSince(viewStartTime).dd_toInt64Nanoseconds
        XCTAssertEqual(actualTNS, expectedTNS, "TNS should span from the view start to the last completed initial resource.")
    }

    func testWhenViewIsStopped_thenTNSIsNotReported() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default TNS resource predicate)
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
        XCTAssertNil(lastViewEvent.view.networkSettledTime, "TNS should not be reported if view was stopped during resource loading.")
    }

    func testWhenResourceIsDropped_thenItIsExcludedFromTNSMetric() throws {
        let droppedResourceURL: URL = .mockRandom()

        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.resourceEventMapper = { event in // drop resource events
            event.resource.url == droppedResourceURL.absoluteString ? nil : event
        }
        rumConfig.errorEventMapper = { event in // drop resource error events
            event.error.resource?.url == droppedResourceURL.absoluteString ? nil : event
        }

        // Given (default TNS resource predicate)
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
        let actualTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TNS should be reported after initial resources end.")
        let expectedTNS = resource1EndTime.timeIntervalSince(viewStartTime).dd_toInt64Nanoseconds
        XCTAssertEqual(actualTNS, expectedTNS, "TNS should only reflect ACCEPTED resources.")
    }

    func testGivenCustomTNSResourcePredicate_whenViewCompletes_thenTNSMetricIsCalculatedFromClassifiedResources() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given
        let viewLoadingURL1: URL = .mockRandom()
        let viewLoadingURL2: URL = .mockRandom()
        let viewLoadingURL3: URL = .mockRandom()
        let otherURL: URL = .mockRandom()

        // We expect TNS to be calculated for URLs 1-3, ignoring other URLs.
        // In this test, resources are started and completed as follows:
        //
        // |-------------- TNS --------------|
        // |   [··· URL 1 ···]
        // |        [·········· OTHER URL ··········]
        // |                  [···· URL 2 ····]
        // |                  [·· URL 3 ··]
        //
        // ^ Start of the view                ^ End of the last classified resource

        struct CustomPredicate: NetworkSettledResourcePredicate {
            let viewLoadingURLs: Set<URL>

            func isInitialResource(from resourceParams: TNSResourceParams) -> Bool {
                resourceParams.viewName == "FooView" && viewLoadingURLs.contains(URL(string: resourceParams.url)!)
            }
        }

        rumConfig.networkSettledResourcePredicate = CustomPredicate(
            viewLoadingURLs: [viewLoadingURL1, viewLoadingURL2, viewLoadingURL3]
        )
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)
        let viewStartTime = rumTime.now

        // When (start view)
        monitor.startView(key: "view", name: "FooView")
        rumTime.now += 0.15.seconds

        // When (start view-initial resource)
        monitor.startResource(resourceKey: "resource1", url: viewLoadingURL1)
        rumTime.now += 0.5.seconds

        // When (start resource unrelated to view loading)
        monitor.startResource(resourceKey: "resourceX", url: otherURL)
        rumTime.now += 0.5.seconds

        // When (complete view-initial resource and start two more)
        monitor.stopResource(resourceKey: "resource1", response: .mockAny())
        monitor.startResource(resourceKey: "resource2", url: viewLoadingURL2)
        monitor.startResource(resourceKey: "resource3", url: viewLoadingURL3)
        rumTime.now += 1.5.seconds

        // When (complete all pending resources)
        monitor.stopResource(resourceKey: "resource3", response: .mockAny())
        rumTime.now += 0.25.seconds
        monitor.stopResource(resourceKey: "resource2", response: .mockAny())
        let lastInitialResourceCompletionTime = rumTime.now
        rumTime.now += 0.5.seconds
        monitor.stopResource(resourceKey: "resourceX", response: .mockAny())

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let lastViewEvent = try XCTUnwrap(session.views.last?.viewEvents.last)
        let actualTNS = try XCTUnwrap(lastViewEvent.view.networkSettledTime, "TNS should be reported after initial resources complete loading.")
        let expectedTNS = lastInitialResourceCompletionTime.timeIntervalSince(viewStartTime).dd_toInt64Nanoseconds
        XCTAssertEqual(actualTNS, expectedTNS, "TNS should span from the view start to the completion of last classified resource.")
    }

    // MARK: - Interaction To Next View

    func testWhenActionOccursInPreviousView_andNextViewStarts_thenINVIsTrackedForNextView() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default INV action predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view is started within the INV threshold after the action)
        let expectedINV: TimeInterval = .mockRandom(
            min: 0, max: TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.99
        )
        rumTime.now += expectedINV
        monitor.startView(key: "next", name: "NextView")

        // Then (INV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualINV = try XCTUnwrap(nextViewEvent.view.interactionToNextViewTime)
        XCTAssertEqual(TimeInterval(dd_fromNanoseconds: actualINV), expectedINV, accuracy: 0.01)
    }

    func testWhenActionOccursInPreviousView_andNextViewStartsAfterThreshold_thenINVIsNotTrackedForNextView() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default INV action predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view starts after exceeding the INV threshold)
        rumTime.now += TimeBasedINVActionPredicate.defaultMaxTimeToNextView + 0.01 // exceeds the max threshold
        monitor.startView(key: "next", name: "NextView")

        // Then (INV is not tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualINV = nextViewEvent.view.interactionToNextViewTime
        XCTAssertNil(actualINV, "The INV value should not be tracked when the next view starts after exceeding the threshold.")
    }

    func testWhenMultipleActionsOccursInPreviousView_thenINVIsMeasuredFromTheLastAction() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default INV action predicate)
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

        // When (the next view is started within the INV threshold after last action)
        let expectedINV: TimeInterval = .mockRandom(
            min: 0, max: TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.99
        )
        rumTime.now += expectedINV
        monitor.startView(key: "next", name: "NextView")

        // Then (INV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualINV = try XCTUnwrap(nextViewEvent.view.interactionToNextViewTime)
        XCTAssertEqual(TimeInterval(dd_fromNanoseconds: actualINV), expectedINV, accuracy: 0.01)
    }

    func testWhenActionInPreviousViewIsDropped_thenINVIsNotTracked() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.actionEventMapper = { event in
            event.action.target?.name == "Tap in Previous View" ? nil : event // drop "Tap in Previous View"
        }

        // Given (default INV action predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (an action occurs in the previous view - which will be dropped)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view is started within the INV threshold after the action)
        rumTime.now += TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.5
        monitor.startView(key: "next", name: "NextView")

        // Then (INV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        XCTAssertNil(nextViewEvent.view.interactionToNextViewTime, "The INV value should not be tracked when the action is dropped.")
    }

    func testINVIsOnlyTrackedForViewsThatWereStartedDueToAnAction() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // Given (default INV action predicate)
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When (start the previous view and add an action)
        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view starts due to the action)
        rumTime.now += TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.5
        monitor.startView(key: "next", name: "NextView")

        // When (a new view starts without an action)
        rumTime.now += TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.5
        monitor.startView(key: "nextWithoutAction", name: "NextViewWithoutAction")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let nextViewWithoutAction = try XCTUnwrap(session.views.first(where: { $0.name == "NextViewWithoutAction" })?.viewEvents.last)
        XCTAssertNotNil(nextViewEvent.view.interactionToNextViewTime, "INV should be tracked for view that started due to an action.")
        XCTAssertNil(nextViewWithoutAction.view.interactionToNextViewTime, "INV should not be tracked for view that started without an action.")
    }

    func testGivenCustomINVActionPredicate_whenNextViewStarts_thenINVMetricIsCalculatedFromClassifiedActions() throws {
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime

        // We expect INV for "WelcomeView" to be calculated from "Sign Up" action:
        //
        // [········· LoginView ·········][········· WelcomeView ·········]
        //    (A0)        (A1)  (A2)
        //                |---- INV -----|
        //                ^ "last interaction"
        //`                               ^ Start of the next view
        //
        // - A1 - "Sign Up" action; classified by predicate
        // - A0, A2 - other actions; ignored by predicate

        struct CustomINVPredicate: NextViewActionPredicate {
            func isLastAction(from actionParams: INVActionParams) -> Bool {
                return actionParams.name == "Sign Up" && actionParams.nextViewName == "WelcomeView"
            }
        }

        // Use the custom predicate
        rumConfig.nextViewActionPredicate = CustomINVPredicate()
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // Start the previous view
        monitor.startView(key: "login", name: "LoginView")
        rumTime.now += 1.0.seconds

        // Track a custom action with a different name, which won't match our predicate
        monitor.addAction(type: .tap, name: "A0")

        // Track the "Sign Up" action, which should match our custom predicate
        rumTime.now += 0.5.seconds
        monitor.addAction(type: .tap, name: "Sign Up")

        let expectedINV: TimeInterval = 2.0
        rumTime.now += expectedINV * 0.25
        monitor.addAction(type: .tap, name: "A1")

        // After 2 seconds, start the next view with name "WelcomeView"
        rumTime.now += expectedINV * 0.75
        monitor.startView(key: "welcome", name: "WelcomeView")

        // Collect and inspect RUM events
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // Find the final `view` event for "WelcomeView"
        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "WelcomeView" })?.viewEvents.last)

        // Check the INV metric
        let actualINV = try XCTUnwrap(nextViewEvent.view.interactionToNextViewTime)
        XCTAssertEqual(
            TimeInterval(dd_fromNanoseconds: actualINV),
            expectedINV,
            accuracy: 0.01,
            "The INV value should be computed from the last 'Sign Up' action that leads to 'WelcomeView'."
        )
    }

    func testGivenDisabledINV_thenViewEventHasNoINVValue() throws {
        // This duplicates the first INV test, but ensures that INV has no value when it is disabled
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.nextViewActionPredicate = nil
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        // When (the next view is started within the INV threshold after the action)
        let expectedINV: TimeInterval = .mockRandom(
            min: 0, max: TimeBasedINVActionPredicate.defaultMaxTimeToNextView * 0.99
        )
        rumTime.now += expectedINV
        monitor.startView(key: "next", name: "NextView")

        // Then (INV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualINV = nextViewEvent.view.interactionToNextViewTime
        XCTAssertNil(actualINV)
    }

    func testGivenDisabledINV_whenGivenCustomINVValue_thenViewEventHasCustomINVValue() throws {
        // This duplicates the first INV test with a custom INV value added in.
        let rumTime = DateProviderMock()
        rumConfig.dateProvider = rumTime
        rumConfig.nextViewActionPredicate = nil
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        monitor.startView(key: "previous", name: "PreviousView")
        rumTime.now += 2.seconds
        monitor.addAction(type: .tap, name: "Tap in Previous View")

        let nextTime: TimeInterval = .mockRandom(
            min: 0, max: 2.5
        )
        rumTime.now += nextTime
        monitor.startView(key: "next", name: "NextView")
        monitor._internal?.setInternalViewAttribute(
            at: .mockAny(),
            key: CrossPlatformAttributes.customINVValue,
            value: 180_000
        )
        // Force a view update
        monitor.stopView(key: "next")

        // Then (INV is tracked for the next view)
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let nextViewEvent = try XCTUnwrap(session.views.first(where: { $0.name == "NextView" })?.viewEvents.last)
        let actualINV = nextViewEvent.view.interactionToNextViewTime
        XCTAssertEqual(180_000, actualINV)
    }
}
