/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogLogs

/// Tests covering Core SDK context propagation into recorded logs: user info (`usr.*`) and
/// account info (`account.*`) populated by the global `Datadog.setUserInfo`/`setAccountInfo`
/// surface and surfaced on every subsequent log.
///
/// See `Datadog/IntegrationUnitTests/Logs/SCENARIOS.md` for the full list of scenarios this file covers.
class LogsContextEnrichmentTests: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    private let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()`).
    private let timeToSDKInit: TimeInterval = 0.7

    // MARK: - §13 User info & account info

    func testGivenSDKInitialized_whenUserInfoIsSet_subsequentLogsCarryUsrIdNameAndEmail() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.setUserInfo(id: "u1", name: "Alice", email: "alice@x.com"))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("after user info set")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let userId: String = try log.value(forKeyPath: "usr.id")
        let userName: String = try log.value(forKeyPath: "usr.name")
        let userEmail: String = try log.value(forKeyPath: "usr.email")
        XCTAssertEqual(userId, "u1")
        XCTAssertEqual(userName, "Alice")
        XCTAssertEqual(userEmail, "alice@x.com")
    }

    func testGivenUserInfoWithExtraInfo_whenLogIsEmitted_extraInfoKeysAppearUnderUsrPrefix() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.setUserInfo(id: "u1", extraInfo: ["plan": "pro", "seats": 10]))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("after extra info set")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let plan: String = try log.value(forKeyPath: "usr.plan")
        let seats: Int = try log.value(forKeyPath: "usr.seats")
        XCTAssertEqual(plan, "pro")
        XCTAssertEqual(seats, 10)
    }

    func testGivenUserInfoSet_whenAddUserExtraInfoIsCalled_subsequentLogsCarryMergedFields() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.setUserInfo(id: "u1", name: "Alice", email: "alice@x.com", extraInfo: ["k1": "v1"]))
            .and(.addUserExtraInfo(["k2": "v2"]))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("after merge")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let userId: String = try log.value(forKeyPath: "usr.id")
        let userName: String = try log.value(forKeyPath: "usr.name")
        let userEmail: String = try log.value(forKeyPath: "usr.email")
        let k1: String = try log.value(forKeyPath: "usr.k1")
        let k2: String = try log.value(forKeyPath: "usr.k2")
        XCTAssertEqual(userId, "u1")
        XCTAssertEqual(userName, "Alice")
        XCTAssertEqual(userEmail, "alice@x.com")
        XCTAssertEqual(k1, "v1")
        XCTAssertEqual(k2, "v2")
    }

    func testGivenUserExtraInfoKey_whenAddUserExtraInfoSetsThatKeyToNil_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.setUserInfo(id: "u1", extraInfo: ["k": "v"]))
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("before nil removal")
            }
            .and(.addUserExtraInfo(["k": nil]))
            .when { app in
                app.logger.info("after nil removal")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2)
        let logBefore = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "before nil removal" })
        let logAfter = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "after nil removal" })
        let beforeK: String = try logBefore.value(forKeyPath: "usr.k")
        XCTAssertEqual(beforeK, "v")
        logAfter.assertNoValue(forKey: "usr.k")
    }

    func testGivenUserInfoSet_whenClearUserInfoIsCalled_subsequentLogsHaveNoUsrIdNameOrEmail() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .and(.setUserInfo(id: "u1", name: "Alice", email: "alice@x.com", extraInfo: ["k": "v"]))
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("before clear")
            }
            .and(.clearUserInfo())
            .when { app in
                app.logger.info("after clear")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2)
        let logBefore = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "before clear" })
        let logAfter = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "after clear" })
        let beforeId: String = try logBefore.value(forKeyPath: "usr.id")
        XCTAssertEqual(beforeId, "u1")
        logAfter.assertNoValue(forKey: "usr.id")
        logAfter.assertNoValue(forKey: "usr.name")
        logAfter.assertNoValue(forKey: "usr.email")
        logAfter.assertNoValue(forKey: "usr.k")
        let anonAfter: String = try logAfter.value(forKeyPath: "usr.anonymous_id")
        XCTAssertFalse(anonAfter.isEmpty)
    }

    func testGivenLogEmittedBeforeUserInfoSet_whenLaterLogIsEmitted_onlyLaterLogCarriesUsrId() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("before user info")
            }
            .and(.setUserInfo(id: "u1", name: "Alice", email: "alice@x.com"))
            .when { app in
                app.logger.info("after user info")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2)
        let logBefore = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "before user info" })
        let logAfter = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "after user info" })
        logBefore.assertNoValue(forKey: "usr.id")
        logBefore.assertNoValue(forKey: "usr.name")
        logBefore.assertNoValue(forKey: "usr.email")
        let afterId: String = try logAfter.value(forKeyPath: "usr.id")
        let afterName: String = try logAfter.value(forKeyPath: "usr.name")
        let afterEmail: String = try logAfter.value(forKeyPath: "usr.email")
        XCTAssertEqual(afterId, "u1")
        XCTAssertEqual(afterName, "Alice")
        XCTAssertEqual(afterEmail, "alice@x.com")
    }

    func testGivenNoExplicitUserInfo_whenLogIsEmitted_logCarriesNonEmptyAnonymousId() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("no user info set")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let anonId: String = try log.value(forKeyPath: "usr.anonymous_id")
        XCTAssertFalse(anonId.isEmpty)
        log.assertNoValue(forKey: "usr.id")
        log.assertNoValue(forKey: "usr.name")
        log.assertNoValue(forKey: "usr.email")
    }

    func testGivenAccountInfoSet_whenLogIsEmitted_logCarriesAccountIdAndAccountName() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                app.core.setAccountInfo(id: "acc1", name: "Acme", extraInfo: [:])
            }
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("after account info set")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let accountId: String = try log.value(forKeyPath: "account.id")
        let accountName: String = try log.value(forKeyPath: "account.name")
        XCTAssertEqual(accountId, "acc1")
        XCTAssertEqual(accountName, "Acme")
    }

    // MARK: - §14 Network info

    func testGivenDefaultLoggerConfiguration_whenLogIsEmitted_logCarriesNoNetworkClientFields() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("default network info disabled")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        log.assertNoValue(forKey: "network.client.reachability")
        log.assertNoValue(forKey: "network.client.available_interfaces")
        log.assertNoValue(forKey: "network.client.supports_ipv4")
        log.assertNoValue(forKey: "network.client.supports_ipv6")
        log.assertNoValue(forKey: "network.client.is_expensive")
        log.assertNoValue(forKey: "network.client.is_constrained")
        log.assertNoValue(forKey: "network.client.link_quality")
        log.assertNoValue(forKey: "network.client.sim_carrier.name")
        log.assertNoValue(forKey: "network.client.sim_carrier.iso_country")
        log.assertNoValue(forKey: "network.client.sim_carrier.technology")
        log.assertNoValue(forKey: "network.client.sim_carrier.allows_voip")
    }
}
