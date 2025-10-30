/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class SessionEndedMetricTests: XCTestCase {
    private typealias Constants = SessionEndedMetric.Constants
    private typealias SessionEndedAttributes = SessionEndedMetric.Attributes
    private let sessionID: RUMUUID = .mockRandom()

    func testReportingEmptyMetric() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertNil(rse.duration)
        XCTAssertEqual(rse.viewsCount.total, 0)
        XCTAssertEqual(rse.viewsCount.background, 0)
        XCTAssertEqual(rse.viewsCount.applicationLaunch, 0)
        XCTAssertEqual(rse.actionsCount.total, 0)
        XCTAssertEqual(rse.sdkErrorsCount.total, 0)
        XCTAssertEqual(rse.sdkErrorsCount.byKind, [:])
        XCTAssertNil(rse.lifecycleInfo)
    }

    // MARK: - Metric Type

    func testReportingMetricType() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        XCTAssertEqual(attributes[SDKMetricFields.typeKey] as? String, Constants.typeValue)
    }

    // MARK: - Session ID

    func testReportingSessionID() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        XCTAssertEqual(attributes[SDKMetricFields.sessionIDOverrideKey] as? String, sessionID.toRUMDataFormat)
    }

    // MARK: - Process Type

    func testReportingAppProcessType() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID, context: .mockWith(applicationBundleType: .iOSApp))

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.processType, "app")
    }

    func testReportingExtensionProcessType() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID, context: .mockWith(applicationBundleType: .iOSAppExtension))

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.processType, "extension")
    }

    // MARK: - Precondition

    func testReportingSessionPrecondition() throws {
        // Given
        let expectedPrecondition: RUMSessionPrecondition = .mockRandom()
        let metric = SessionEndedMetric.with(sessionID: sessionID, precondition: expectedPrecondition)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.precondition, expectedPrecondition.rawValue)
    }

    // MARK: - Tracks Background Events

    func testReportingTracksBackgroundEvents() throws {
        // Given
        let expected: Bool = .mockRandom()
        let metric = SessionEndedMetric.with(sessionID: sessionID, tracksBackgroundEvents: expected)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.hasBackgroundEventsTrackingEnabled, expected)
    }

    // MARK: - Duration

    func testComputingDurationFromSingleView() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)
        let view: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue)

        // When
        try metric.track(view: view, instrumentationType: nil)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, view.view.timeSpent)
    }

    func testComputingDurationFromMultipleViews() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)
        let view1: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 10.s2ms, viewTimeSpent: 10.s2ns)
        let view2: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 10.s2ms + 10.s2ms, viewTimeSpent: 20.s2ns)
        let view3: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 10.s2ms + 10.s2ms + 20.s2ms, viewTimeSpent: 50.s2ns)

        // When
        try metric.track(view: view1, instrumentationType: nil)
        try metric.track(view: view2, instrumentationType: nil)
        try metric.track(view: view3, instrumentationType: nil)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 10.s2ns + 20.s2ns + 50.s2ns)
    }

    func testComputingDurationFromOverlappingViews() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)
        let view1: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 10.s2ms, viewTimeSpent: 10.s2ns)
        let view2: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 15.s2ms, viewTimeSpent: 20.s2ns) // starts in the middle of `view1`

        // When
        try metric.track(view: view1, instrumentationType: nil)
        try metric.track(view: view2, instrumentationType: nil)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 25.s2ns)
    }

    func testDurationIsAlwaysComputedFromTheFirstAndLastView() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)
        let firstView: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 5.s2ms, viewTimeSpent: 10.s2ns)
        let lastView: RUMViewEvent = .mockRandomWith(sessionID: sessionID.rawValue, date: 5.s2ms + 10.s2ms, viewTimeSpent: 20.s2ns)

        // When
        try metric.track(view: firstView, instrumentationType: nil)
        try (0..<10).forEach { _ in try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue), instrumentationType: nil) } // middle views should not alter the duration
        try metric.track(view: lastView, instrumentationType: nil)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 10.s2ns + 20.s2ns)
    }

    func testWhenComputingDuration_itIgnoresViewsFromDifferentSession() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        XCTAssertThrowsError(try metric.track(view: .mockRandom(), instrumentationType: nil))
        XCTAssertThrowsError(try metric.track(view: .mockRandom(), instrumentationType: nil))
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertNil(rse.duration)
    }

    // MARK: - Was Stopped

    func testReportingSessionThatWasStopped() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        metric.trackWasStopped()
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertTrue(rse.wasStopped)
    }

    func testReportingSessionThatWasNotStopped() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertFalse(rse.wasStopped)
    }

    // MARK: - NTP Offset

    func testReportingNTPOffset() throws {
        let offsetAtStart: TimeInterval = .mockRandom(min: -10, max: 10)
        let offsetAtEnd: TimeInterval = .mockRandom(min: -10, max: 10)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID, context: .mockWith(serverTimeOffset: offsetAtStart))

        // When
        let attributes = metric.asMetricAttributes(with: .mockWith(serverTimeOffset: offsetAtEnd))

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.ntpOffset.atStart, offsetAtStart.toInt64Milliseconds)
        XCTAssertEqual(rse.ntpOffset.atEnd, offsetAtEnd.toInt64Milliseconds)
    }

    // MARK: - Views Count

    func testReportingTotalViewsCount() throws {
        let viewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try viewIDs.forEach { try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: $0), instrumentationType: nil) }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, viewIDs.count)
    }

    func testWhenReportingTotalViewsCount_itCountsEachViewIDOnlyOnce() throws {
        let viewID1: String = .mockRandom()
        let viewID2: String = .mockRandom(otherThan: [viewID1])

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try (0..<5).forEach { _ in // repeat few times
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: viewID1), instrumentationType: nil)
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: viewID2), instrumentationType: nil)
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, 2)
    }

    func testReportingBackgroundViewsCount() throws {
        let backgroundViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let otherViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let viewIDs = backgroundViewIDs.union(otherViewIDs)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try viewIDs.forEach { viewID in
            let viewURL = backgroundViewIDs.contains(viewID) ? RUMOffViewEventsHandlingRule.Constants.backgroundViewURL : .mockRandom()
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: viewID, viewURL: viewURL), instrumentationType: nil)
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.background, backgroundViewIDs.count)
    }

    func testReportingApplicationLaunchViewsCount() throws {
        let appLaunchViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let otherViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let viewIDs = appLaunchViewIDs.union(otherViewIDs)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try viewIDs.forEach { viewID in
            let viewURL = appLaunchViewIDs.contains(viewID) ? RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL : .mockRandom()
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: viewID, viewURL: viewURL), instrumentationType: nil)
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.applicationLaunch, appLaunchViewIDs.count)
    }

    func testReportingViewsCountByInstrumentationType() throws {
        let manualViewsCount: Int = .mockRandom(min: 1, max: 10)
        let swiftuiViewsCount: Int = .mockRandom(min: 1, max: 10)
        let uikitPredicateViewsCount: Int = .mockRandom(min: 1, max: 10)
        let swiftuiAutomaticPredicateViewsCount: Int = .mockRandom(min: 1, max: 10)
        let unknownViewsCount: Int = .mockRandom(min: 1, max: 10)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try (0..<manualViewsCount).forEach { idx in
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "manual\(idx)"), instrumentationType: .manual)
        }
        try (0..<swiftuiViewsCount).forEach { idx in
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "swiftui\(idx)"), instrumentationType: .swiftui)
        }
        try (0..<uikitPredicateViewsCount).forEach { idx in
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "uikit\(idx)"), instrumentationType: .uikit)
        }
        try (0..<swiftuiAutomaticPredicateViewsCount).forEach { idx in
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "swiftuiAutomatic\(idx)"), instrumentationType: .swiftuiAutomatic)
        }
        try (0..<unknownViewsCount).forEach { idx in
            try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "unknown\(idx)"), instrumentationType: nil)
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, manualViewsCount + swiftuiViewsCount + uikitPredicateViewsCount + swiftuiAutomaticPredicateViewsCount + unknownViewsCount)
        XCTAssertEqual(
            rse.viewsCount.byInstrumentation,
            [
                "manual": manualViewsCount,
                "swiftui": swiftuiViewsCount,
                "uikit": uikitPredicateViewsCount,
                "swiftuiAutomatic": swiftuiAutomaticPredicateViewsCount
            ]
        )
    }

    func testWhenReportingViewsCountByInstrumentationType_itIgnoresSuccedingInstrumentationTypesForGivenViewID() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "view-id"), instrumentationType: .manual)

        // When
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "view-id"), instrumentationType: nil)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "view-id"), instrumentationType: .swiftui)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "view-id"), instrumentationType: .uikit)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "view-id"), instrumentationType: .swiftuiAutomatic)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.byInstrumentation, ["manual": 1])
    }

    func testReportingHasReplayViewsCount() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "1", hasReplay: nil), instrumentationType: nil)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "1", hasReplay: false), instrumentationType: nil)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "1", hasReplay: true), instrumentationType: nil) // count
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "2", hasReplay: false), instrumentationType: nil)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "3", hasReplay: true), instrumentationType: nil) // count
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewID: "3", hasReplay: false), instrumentationType: nil) // ignore
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, 3)
        XCTAssertEqual(rse.viewsCount.withHasReplay, 2)
    }

    func testWhenReportingViewsCount_itIgnoresViewsFromDifferentSession() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        XCTAssertThrowsError(try metric.track(view: .mockRandom(), instrumentationType: nil))
        XCTAssertThrowsError(try metric.track(view: .mockRandom(), instrumentationType: nil))
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, 0)
    }

    // MARK: - Actions Count

    func testReportingTotalActionsCount() throws {
        let actionCount: Int = .mockRandom(min: 1, max: 10)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        (0..<actionCount).forEach { _ in
            metric.track(
                action: .mockWith(sessionID: sessionID.rawValue),
                instrumentationType: .manual
            )
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.actionsCount.total, actionCount)
    }

    func testReportingActionsCountByInstrumentationType() throws {
        let manualActionsCount: Int = .mockRandom(min: 1, max: 10)
        let swiftuiActionsCount: Int = .mockRandom(min: 1, max: 10)
        let uikitPredicateActionsCount: Int = .mockRandom(min: 1, max: 10)
        let swiftuiAutomaticPredicateActionsCount: Int = .mockRandom(min: 1, max: 10)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        (0..<manualActionsCount).forEach { _ in
            metric.track(
                action: .mockWith(sessionID: sessionID.rawValue),
                instrumentationType: .manual
            )
        }
        (0..<swiftuiActionsCount).forEach { _ in
            metric.track(
                action: .mockWith(sessionID: sessionID.rawValue),
                instrumentationType: .swiftui
            )
        }
        (0..<uikitPredicateActionsCount).forEach { _ in
            metric.track(
                action: .mockWith(sessionID: sessionID.rawValue),
                instrumentationType: .uikit
            )
        }
        (0..<swiftuiAutomaticPredicateActionsCount).forEach { _ in
            metric.track(
                action: .mockWith(sessionID: sessionID.rawValue),
                instrumentationType: .swiftuiAutomatic
            )
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(
            rse.actionsCount.total,
            manualActionsCount + swiftuiActionsCount + uikitPredicateActionsCount + swiftuiAutomaticPredicateActionsCount
        )
        XCTAssertEqual(
            rse.actionsCount.byInstrumentation,
            [
                "manual": manualActionsCount,
                "swiftui": swiftuiActionsCount,
                "uikit": uikitPredicateActionsCount,
                "swiftuiAutomatic": swiftuiAutomaticPredicateActionsCount
            ]
        )
    }

    func testWhenReportingActionsCount_itIgnoresActionsFromDifferentSession() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        metric.track(action: .mockAny(), instrumentationType: .manual)
        metric.track(action: .mockAny(), instrumentationType: .manual)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.actionsCount.total, 0)
        XCTAssertEqual(rse.actionsCount.byInstrumentation, [:])
    }

    // MARK: - SDK Errors Count

    func testReportingTotalSDKErrorsCount() throws {
        let errorKinds: [String] = .mockRandom(count: .mockRandom(min: 0, max: 10))
        let repetitions = 5

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        (0..<repetitions).forEach { _ in
            errorKinds.forEach { metric.track(sdkErrorKind: $0) }
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.sdkErrorsCount.total, errorKinds.count * repetitions)
    }

    func testReportingTopSDKErrorsCount() throws {
        let errorKinds: [String: Int] = [
            "top1": 9, "top2": 8, "top3": 7, "top4": 6,
            "top5": 5, "top6": 4, "top7": 3, "top8": 2,
        ]

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        errorKinds.forEach { kind, count in
            (0..<count).forEach { _ in metric.track(sdkErrorKind: kind) }
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(
            rse.sdkErrorsCount.byKind,
            ["top1": 9, "top2": 8, "top3": 7, "top4": 6, "top5": 5]
        )
    }

    func testWhenReportingTopSDKErrorsCount_itEscapesTheKind() throws {
        let errorKinds: [String: Int] = [
            "top 1 error": 9, "top: 2 error": 8, "top_3_error": 7, "top4/error": 6,
        ]

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        errorKinds.forEach { kind, count in
            (0..<count).forEach { _ in metric.track(sdkErrorKind: kind) }
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(
            rse.sdkErrorsCount.byKind,
            ["top_1_error": 9, "top__2_error": 8, "top_3_error": 7, "top4_error": 6]
        )
    }

    // MARK: - No View Events Count

    func testReportingMissedEventsCount() throws {
        let missedActionsCount: Int = .mockRandom(min: 1, max: 10)
        let missedResourcesCount: Int = .mockRandom(min: 1, max: 10)
        let missedErrorsCount: Int = .mockRandom(min: 1, max: 10)
        let missedLongTasksCount: Int = .mockRandom(min: 1, max: 10)

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID)

        // When
        (0..<missedActionsCount).forEach { _ in metric.track(missedEventType: .action) }
        (0..<missedResourcesCount).forEach { _ in metric.track(missedEventType: .resource) }
        (0..<missedErrorsCount).forEach { _ in metric.track(missedEventType: .error) }
        (0..<missedLongTasksCount).forEach { _ in metric.track(missedEventType: .longTask) }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.noViewEventsCount.actions, missedActionsCount)
        XCTAssertEqual(rse.noViewEventsCount.resources, missedResourcesCount)
        XCTAssertEqual(rse.noViewEventsCount.errors, missedErrorsCount)
        XCTAssertEqual(rse.noViewEventsCount.longTasks, missedLongTasksCount)
    }

    // MARK: - Tracks Upload Quality

    func testUploadQualityMetricAggregation() throws {
        let metric = SessionEndedMetric.with(sessionID: sessionID, context: .mockWith(applicationBundleType: .iOSApp))
        metric.track(uploadQuality: [
            UploadQualityMetric.track: "feature",
            UploadQualityMetric.failure: "error1"
        ])

        metric.track(uploadQuality: [
            UploadQualityMetric.track: "feature",
            UploadQualityMetric.failure: "error1",
            UploadQualityMetric.blockers: ["blocker1", "blocker2"]
        ])

        metric.track(uploadQuality: [
            UploadQualityMetric.track: "feature",
        ])

        metric.track(uploadQuality: [
            UploadQualityMetric.track: "feature",
            UploadQualityMetric.failure: "error2",
            UploadQualityMetric.blockers: ["blocker1"]
        ])

        // When
        let matcher = try JSONObjectMatcher(AnyEncodable(metric.asMetricAttributes()))

        XCTAssertEqual(try matcher.value("rse.upload_quality.feature.cycle_count") as Int, 4)
        XCTAssertEqual(try matcher.value("rse.upload_quality.feature.failure_count.error1") as Int, 2)
        XCTAssertEqual(try matcher.value("rse.upload_quality.feature.failure_count.error2") as Int, 1)
        XCTAssertEqual(try matcher.value("rse.upload_quality.feature.blocker_count.blocker1") as Int, 2)
        XCTAssertEqual(try matcher.value("rse.upload_quality.feature.blocker_count.blocker2") as Int, 1)
    }

    // MARK: - Launch Info

    func testReportingLaunchInfo() throws {
        let prewarmed: Bool = .mockRandom()
        let isUsingSceneLifecycle: Bool = .mockRandom()
        let processLaunchDate = Date()
        let launchInfo = LaunchInfo(
            launchReason: .userLaunch,
            processLaunchDate: processLaunchDate,
            runtimeLoadDate: nil,
            runtimePreMainDate: nil,
            didFinishLaunchingDate: nil,
            didBecomeActiveDate: processLaunchDate.addingTimeInterval(1.84),
            raw: .init(taskPolicyRole: "TASK_ROLE_MOCK", isPrewarmed: prewarmed)
        )
        let sdkInitDate = launchInfo.processLaunchDate + 0.42
        let context: DatadogContext = .mockWith(
            sdkInitDate: sdkInitDate,
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(initialState: .inactive, date: sdkInitDate)
        )

        // Given
        let metric = SessionEndedMetric.with(
            sessionID: sessionID,
            context: context,
            isUsingSceneLifecycle: isUsingSceneLifecycle
        )

        // When
        let attributes = metric.asMetricAttributes(with: context)

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.launchInfo.launchReason, "user launch")
        XCTAssertEqual(rse.launchInfo.taskRole, "TASK_ROLE_MOCK")
        XCTAssertEqual(rse.launchInfo.prewarmed, prewarmed)
        XCTAssertEqual(rse.launchInfo.timeToSdkInit, sdkInitDate.timeIntervalSince(launchInfo.processLaunchDate).toInt64Milliseconds)
        XCTAssertEqual(rse.launchInfo.timeToDidBecomeActive, 1.84.toInt64Milliseconds)
        XCTAssertEqual(rse.launchInfo.hasScenesLifecycle, isUsingSceneLifecycle)
        XCTAssertEqual(rse.launchInfo.appStateAtSdkInit, "inactive")
    }

    // MARK: - Lifecycle Info

    func testReportingLifecycleInfo() throws {
        let processLaunchDate = Date()
        let view1Start = processLaunchDate + 1
        let view1Stop = view1Start + 10 // view1 lasts for 10s
        let view2Start = view1Stop + 4 // 4s in background, then view2 starts
        let view2Stop = view2Start + 5 // view2 lasts for 5s
        let validSessionCount: Int = .mockRandom()

        let context: DatadogContext = .mockWith(
            launchInfo: .mockWith(processLaunchDate: processLaunchDate),
            applicationStateHistory: .mockWith(
                initialState: .inactive,
                date: processLaunchDate,
                transitions: [
                    (.background, view1Stop), // background on "view1 stop"
                    (.active, view2Start), // foreground on "view2 start"
                ]
            )
        )

        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID, validSessionCount: validSessionCount)

        // When
        try metric.track(
            view: .mockRandomWith(
                sessionID: sessionID.rawValue,
                viewID: "view1",
                date: view1Start.timeIntervalSince1970.toInt64Milliseconds,
                viewTimeSpent: (view1Stop.timeIntervalSince(view1Start)).toInt64Nanoseconds
            ),
            instrumentationType: .manual
        )
        try metric.track(
            view: .mockRandomWith(
                sessionID: sessionID.rawValue,
                viewID: "view2",
                date: view2Start.timeIntervalSince1970.toInt64Milliseconds,
                viewTimeSpent: (view2Stop.timeIntervalSince(view2Start)).toInt64Nanoseconds
            ),
            instrumentationType: .manual
        )
        let attributes = metric.asMetricAttributes(with: context)

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.lifecycleInfo?.timeToSessionStart, view1Start.timeIntervalSince(processLaunchDate).toInt64Milliseconds)
        XCTAssertEqual(rse.lifecycleInfo?.sessionsCount, validSessionCount)
        XCTAssertEqual(rse.lifecycleInfo?.appStateAtSessionStart, "inactive")
        XCTAssertEqual(rse.lifecycleInfo?.appStateAtSessionEnd, "active")
        DDAssertEqual(rse.lifecycleInfo?.foregroundCoverage, (10 + 5) / (10 + 4 + 5), accuracy: 0.001)
    }

    // MARK: - Metric Spec

    func testEncodedMetricAttributesFollowTheSpec() throws {
        // Given
        let metric = SessionEndedMetric.with(sessionID: sessionID, context: .mockWith(applicationBundleType: .iOSApp))
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewTimeSpent: 10), instrumentationType: .manual)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewTimeSpent: 10), instrumentationType: .swiftui)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewTimeSpent: 10), instrumentationType: .uikit)
        try metric.track(view: .mockRandomWith(sessionID: sessionID.rawValue, viewTimeSpent: 10), instrumentationType: .swiftuiAutomatic)
        metric.track(uploadQuality: [UploadQualityMetric.track: "feature"])

        // When
        let matcher = try JSONObjectMatcher(AnyEncodable(metric.asMetricAttributes()))

        // Then
        XCTAssertNotNil(try matcher.value("rse.process_type") as String)
        XCTAssertNotNil(try matcher.value("rse.precondition") as String)
        XCTAssertNotNil(try matcher.value("rse.duration") as Int)
        XCTAssertNotNil(try matcher.value("rse.was_stopped") as Bool)
        XCTAssertNotNil(try matcher.value("rse.has_background_events_tracking_enabled") as Bool)
        XCTAssertNotNil(try matcher.value("rse.views_count.total") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.background") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.app_launch") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.by_instrumentation.manual") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.by_instrumentation.swiftui") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.by_instrumentation.uikit") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.by_instrumentation.swiftuiAutomatic") as Int)
        XCTAssertNotNil(try matcher.value("rse.views_count.with_has_replay") as Int)
        XCTAssertNotNil(try matcher.value("rse.sdk_errors_count.total") as Int)
        XCTAssertNotNil(try matcher.value("rse.sdk_errors_count.by_kind") as [String: Int])
        XCTAssertNotNil(try matcher.value("rse.ntp_offset.at_start") as Int)
        XCTAssertNotNil(try matcher.value("rse.ntp_offset.at_end") as Int)
        XCTAssertNotNil(try matcher.value("rse.no_view_events_count.actions") as Int)
        XCTAssertNotNil(try matcher.value("rse.no_view_events_count.resources") as Int)
        XCTAssertNotNil(try matcher.value("rse.no_view_events_count.errors") as Int)
        XCTAssertNotNil(try matcher.value("rse.no_view_events_count.long_tasks") as Int)
        XCTAssertNotNil(try matcher.value("rse.upload_quality.feature.cycle_count") as Int)
    }
}

// MARK: - Helpers

private extension Int {
    /// Converts seconds to milliseconds.
    var s2ms: Int64 { Int64(self) * 1_000 }
    /// Converts seconds to nanoseconds.
    var s2ns: Int64 { Int64(self) * 1_000_000_000 }
    /// Converts nanoseconds to milliseconds.
    var ns2ms: Int64 { Int64(self) / 1_000_000 }
}

private extension SessionEndedMetric {
    static func with(
        sessionID: RUMUUID,
        precondition: RUMSessionPrecondition? = .mockRandom(),
        context: DatadogContext = .mockRandom(),
        tracksBackgroundEvents: Bool = .mockRandom(),
        isUsingSceneLifecycle: Bool = .mockRandom(),
        validSessionCount: Int = .mockRandom()
    ) -> SessionEndedMetric {
        SessionEndedMetric(
            sessionID: sessionID,
            precondition: precondition,
            context: context,
            tracksBackgroundEvents: tracksBackgroundEvents,
            isUsingSceneLifecycle: isUsingSceneLifecycle,
            validSessionCount: validSessionCount
        )
    }

    func asMetricAttributes() -> [String: Encodable] {
        asMetricAttributes(with: .mockRandom())
    }
}
