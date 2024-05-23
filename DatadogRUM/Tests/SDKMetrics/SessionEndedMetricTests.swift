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
    private let sessionID: String = .mockRandom()

    func testReportingEmptyMetric() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertNil(rse.duration)
        XCTAssertEqual(rse.viewsCount.total, 0)
        XCTAssertEqual(rse.viewsCount.background, 0)
        XCTAssertEqual(rse.viewsCount.applicationLaunch, 0)
        XCTAssertEqual(rse.sdkErrorsCount.total, 0)
        XCTAssertEqual(rse.sdkErrorsCount.byKind, [:])
    }

    // MARK: - Metric Type

    func testReportingMetricType() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        XCTAssertEqual(attributes[SDKMetricFields.typeKey] as? String, Constants.typeValue)
    }

    // MARK: - Session ID

    func testReportingSessionID() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        XCTAssertEqual(attributes[Constants.sessionIDKey] as? String, sessionID)
    }

    // MARK: - Process Type

    func testReportingAppProcessType() throws {
        // Given
        let metric = SessionEndedMetric(
            sessionID: sessionID, precondition: .mockRandom(), context: .mockWith(applicationBundleType: .iOSApp)
        )

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.processType, "app")
    }

    func testReportingExtensionProcessType() throws {
        // Given
        let metric = SessionEndedMetric(
            sessionID: sessionID, precondition: .mockRandom(), context: .mockWith(applicationBundleType: .iOSAppExtension)
        )

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
        let metric = SessionEndedMetric(
            sessionID: sessionID, precondition: expectedPrecondition, context: .mockRandom()
        )

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.precondition, expectedPrecondition.rawValue)
    }

    // MARK: - Duration

    func testComputingDurationFromSingleView() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())
        let view: RUMViewEvent = .mockRandomWith(sessionID: sessionID)

        // When
        metric.track(view: view)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, view.view.timeSpent)
    }

    func testComputingDurationFromMultipleViews() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())
        let view1: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 10.s2ms, viewTimeSpent: 10.s2ns)
        let view2: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 10.s2ms + 10.s2ms, viewTimeSpent: 20.s2ns)
        let view3: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 10.s2ms + 10.s2ms + 20.s2ms, viewTimeSpent: 50.s2ns)

        // When
        metric.track(view: view1)
        metric.track(view: view2)
        metric.track(view: view3)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 10.s2ns + 20.s2ns + 50.s2ns)
    }

    func testComputingDurationFromOverlappingViews() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())
        let view1: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 10.s2ms, viewTimeSpent: 10.s2ns)
        let view2: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 15.s2ms, viewTimeSpent: 20.s2ns) // starts in the middle of `view1`

        // When
        metric.track(view: view1)
        metric.track(view: view2)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 25.s2ns)
    }

    func testDurationIsAlwaysComputedFromTheFirstAndLastView() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())
        let firstView: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 5.s2ms, viewTimeSpent: 10.s2ns)
        let lastView: RUMViewEvent = .mockRandomWith(sessionID: sessionID, date: 5.s2ms + 10.s2ms, viewTimeSpent: 20.s2ns)

        // When
        metric.track(view: firstView)
        (0..<10).forEach { _ in metric.track(view: .mockRandom()) } // middle views should not alter the duration
        metric.track(view: lastView)
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.duration, 10.s2ns + 20.s2ns)
    }

    func testWhenComputingDuration_itIgnoresViewsFromDifferentSession() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        metric.track(view: .mockRandom())
        metric.track(view: .mockRandom())
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertNil(rse.duration)
    }

    // MARK: - Was Stopped

    func testReportingSessionThatWasStopped() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        metric.trackWasStopped()
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertTrue(rse.wasStopped)
    }

    func testReportingSessionThatWasNotStopped() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertFalse(rse.wasStopped)
    }

    // MARK: - Views Count

    func testReportingTotalViewsCount() throws {
        let viewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))

        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        viewIDs.forEach { metric.track(view: .mockRandomWith(sessionID: sessionID, viewID: $0)) }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, viewIDs.count)
    }

    func testReportingBackgorundViewsCount() throws {
        let backgroundViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let otherViewIDs: Set<String> = .mockRandom(count: .mockRandom(min: 1, max: 10))
        let viewIDs = backgroundViewIDs.union(otherViewIDs)

        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        viewIDs.forEach { viewID in
            let viewURL = backgroundViewIDs.contains(viewID) ? RUMOffViewEventsHandlingRule.Constants.backgroundViewURL : .mockRandom()
            metric.track(view: .mockRandomWith(sessionID: sessionID, viewID: viewID, viewURL: viewURL))
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
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        viewIDs.forEach { viewID in
            let viewURL = appLaunchViewIDs.contains(viewID) ? RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL : .mockRandom()
            metric.track(view: .mockRandomWith(sessionID: sessionID, viewID: viewID, viewURL: viewURL))
        }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.applicationLaunch, appLaunchViewIDs.count)
    }

    func testReportingViewsCount_itIgnoresViewsFromDifferentSession() throws {
        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        metric.track(view: .mockRandom())
        metric.track(view: .mockRandom())
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.viewsCount.total, 0)
    }

    // MARK: - SDK Errors Count

    func testReportingTotalSDKErrorsCount() throws {
        let errorKinds: [String] = .mockRandom(count: .mockRandom(min: 0, max: 50))

        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

        // When
        errorKinds.forEach { metric.track(sdkErrorKind: $0) }
        let attributes = metric.asMetricAttributes()

        // Then
        let rse = try XCTUnwrap(attributes[Constants.rseKey] as? SessionEndedAttributes)
        XCTAssertEqual(rse.sdkErrorsCount.total, errorKinds.count)
    }

    func testReportingTopSDKErrorsCount() throws {
        let errorKinds: [String: Int] = [
            "top1": 9, "top2": 8, "top3": 7, "top4": 6,
            "top5": 5, "top6": 4, "top7": 3, "top8": 2,
        ]

        // Given
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

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
        let metric = SessionEndedMetric(sessionID: sessionID, precondition: .mockRandom(), context: .mockRandom())

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
}

private extension Int {
    /// Converts seconds to milliseconds.
    var s2ms: Int64 { Int64(self) * 1_000 }
    /// Converts seconds to nanoseconds.
    var s2ns: Int64 { Int64(self) * 1_000_000_000 }
    /// Converts nanoseconds to milliseconds.
    var ns2ms: Int64 { Int64(self) / 1_000_000 }
}
