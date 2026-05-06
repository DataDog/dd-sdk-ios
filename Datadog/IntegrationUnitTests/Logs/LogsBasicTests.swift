/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore
@testable import DatadogLogs
@testable import DatadogRUM

class LogsBasicTests: XCTestCase {
    let processLaunchDate = Date()
    let timeToSDKInit: TimeInterval = 0.7
    let timeToAppBecomeActive: TimeInterval = 0.8
    let dt1: TimeInterval = 1.1
    let dt2: TimeInterval = 1.2

    func testGivenLogsEnabled_whenInfoIsLogged_itIsRecorded() throws {
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.enableLogs())
            .and(.createLogger())
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.advanceTime(by: dt1))
            .when(.withLogger { $0.info("user signed in") })

        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        result.logs[0].assertStatus(equals: "info")
        result.logs[0].assertMessage(equals: "user signed in")
    }

    func testGivenCustomLogger_whenTagIsAddedThenErrorIsLogged_bothPersist() throws {
        struct TestError: Error { let code = 42 }
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.enableLogs())
            .and(.createLogger(setup: { $0.service = "checkout" }))
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.advanceTime(by: dt1))
            .and(.withLogger { $0.addTag(withKey: "feature", value: "promo") })
            .and(.advanceTime(by: dt2))
            .when(.withLogger { logger in
                logger.error("checkout failed", error: TestError())
            })

        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        result.logs[0].assertStatus(equals: "error")
        result.logs[0].assertMessage(equals: "checkout failed")
        result.logs[0].assertService(equals: "checkout")
        // Tag persisted across `withLogger` calls (default logger reused by name).
        // SDK adds globally managed tags (sdk_version, version, env, service) to every log
        // — so we assert that our custom `feature:promo` is present, not that it's the only tag.
        // Note: "env", "host", "device", "source", "service" are reserved and cannot be added by users.
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        XCTAssertTrue(
            tags.split(separator: ",").contains("feature:promo"),
            "Expected 'feature:promo' in ddtags, got: \(tags)"
        )
    }

    func testGivenRUMAndLogsEnabled_whenLogIsEmittedDuringActiveView_itIsBundledWithViewID() throws {
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.enableRUM())
            .and(.enableLogs())
            .and(.createLogger())
            .and(.appBecomesActive(after: timeToAppBecomeActive))
            .and(.appDisplaysFirstFrame())
            .and(.startManualView(after: dt1, viewName: "Cart"))
            .and(.advanceTime(by: dt2))
            .when(.withLogger { $0.warn("cart promo expired") })

        let result = try when.then()
        let session = try result.sessions.takeSingle()
        let view = try XCTUnwrap(session.views.first { $0.name == "Cart" })

        XCTAssertEqual(result.logs.count, 1)
        result.logs[0].assertStatus(equals: "warn")
        result.logs[0].assertMessage(equals: "cart promo expired")
        // bundleWithRumEnabled = true (default) -> log carries view.id of the active RUM view.
        result.logs[0].assertAttributes(equal: ["view.id": view.viewID])
    }
}
