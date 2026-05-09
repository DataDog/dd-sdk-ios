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

/// Tests covering what ends up in the recorded log: levels, message content, dates,
/// thread name, application/build metadata, environment, device/os, `_dd` block.
///
/// See `Datadog/IntegrationUnitTests/Logs/SCENARIOS.md` for the full list of scenarios this file covers.
class LogsRecordingTests: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    private let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()`).
    private let timeToSDKInit: TimeInterval = 0.7

    // MARK: - §3 Log emission (levels & content)

    func testGivenLoggerWithDefaultThreshold_whenLogsAreEmittedAtEachLevel_eachLogCarriesMatchingStatus() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.debug("d")
                app.logger.info("i")
                app.logger.notice("n")
                app.logger.warn("w")
                app.logger.error("e")
                app.logger.critical("c")
            }

        // Then
        let result = try when.then()
        let expectedStatuses = ["debug", "info", "notice", "warn", "error", "critical"]
        XCTAssertEqual(result.logs.count, expectedStatuses.count, "Each emitted log should be recorded")
        for (index, expectedStatus) in expectedStatuses.enumerated() {
            result.logs[index].assertStatus(equals: expectedStatus)
        }
    }

    func testGivenTwoLoggers_whenOneUsesBaseLogMethodAndOtherUsesConvenience_payloadsMatch() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.loggers["base"] = Logger.create(with: Logger.Configuration(name: "base"), in: app.core)
                app.loggers["convenience"] = Logger.create(with: Logger.Configuration(name: "convenience"), in: app.core)
            }
            .when { app in
                app.loggers["base"]?.log(level: .info, message: "shared message", error: nil, attributes: nil)
                app.loggers["convenience"]?.info("shared message")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Exactly two logs should be recorded — one from each logger")

        let baseLog = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "base" })
        let convenienceLog = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "logger.name") as String) == "convenience" })

        // Same status & message
        baseLog.assertStatus(equals: "info")
        convenienceLog.assertStatus(equals: "info")
        baseLog.assertMessage(equals: "shared message")
        convenienceLog.assertMessage(equals: "shared message")

        let baseService: String = try baseLog.value(forKeyPath: "service")
        let convService: String = try convenienceLog.value(forKeyPath: "service")
        XCTAssertEqual(baseService, convService, "Both logs must carry the same service field")

        let baseVersion: String = try baseLog.value(forKeyPath: "logger.version")
        let convVersion: String = try convenienceLog.value(forKeyPath: "logger.version")
        XCTAssertEqual(baseVersion, convVersion, "Both logs must carry the same logger.version field")

        let baseTags: String = try baseLog.value(forKeyPath: "ddtags")
        let convTags: String = try convenienceLog.value(forKeyPath: "ddtags")
        XCTAssertEqual(baseTags, convTags, "Both logs must carry the same ddtags string")
    }

    func testGivenLogger_whenInfoLogIsEmitted_itHasInfoStatusAndMatchingMessage() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("user signed in")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertStatus(equals: "info")
        result.logs[0].assertMessage(equals: "user signed in")
    }

    func testGivenLogger_whenMessageContainsUnicodeAndMultilineContent_itIsPreservedVerbatim() throws {
        let message = "Spëcial 🚀\nMulti\\nLine"

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info(message)
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertMessage(equals: message)
    }

    func testGivenSimulatedTime_whenLogIsEmitted_itsDateMatchesSimulatedTime() throws {
        let extraDelayBeforeEmit: TimeInterval = 1.234

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and(.advanceTime(by: extraDelayBeforeEmit))
            .when { app in
                var config = Logs.Configuration()
                config.dateProvider = app.dateProvider
                Logs.enable(with: config, in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("at-T")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)

        let recordedDateString: String = try result.logs[0].value(forKeyPath: "date")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recordedDate = try XCTUnwrap(parser.date(from: recordedDateString))

        let expectedDate = processLaunchDate.addingTimeInterval(timeToSDKInit + extraDelayBeforeEmit)
        XCTAssertEqual(
            recordedDate.timeIntervalSince1970,
            expectedDate.timeIntervalSince1970,
            accuracy: 0.001,
            "Recorded `date` should match simulated time (processLaunch + advanceTime sum)"
        )
    }

    func testGivenNamedThread_whenLogIsEmitted_loggerThreadNameMatches() throws {
        let threadName = "harness-test-thread"

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)

                let previousName = Thread.current.name
                Thread.current.name = threadName
                defer { Thread.current.name = previousName }
                app.logger.info("from-named-thread")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertThreadName(equals: threadName)
    }

    func testGivenLogger_whenLogIsEmitted_itCarriesApplicationVersionAndBuildNumber() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("version-fields")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")

        let version: String = try result.logs[0].value(forKeyPath: "version")
        let buildVersion: String = try result.logs[0].value(forKeyPath: "build_version")
        XCTAssertFalse(version.isEmpty, "`version` should fall back to a non-empty value sourced from Bundle.main")
        XCTAssertFalse(buildVersion.isEmpty, "`build_version` should fall back to a non-empty value sourced from Bundle.main")
    }

    func testGivenHarnessWithoutCrossPlatformBuildId_whenLogIsEmitted_buildIdIsAbsent() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("build-id-check")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        result.logs[0].assertNoValue(forKey: "build_id")
    }

    func testGivenSDKConfiguredWithCustomEnv_whenLogIsEmitted_itCarriesThatEnvInDdTags() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK(sdkSetup: { config in
                config.env = "harness-env"
            }))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("env-check")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")

        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        XCTAssertTrue(
            tags.split(separator: ",").contains("env:harness-env"),
            "ddtags should contain the SDK-managed `env:harness-env` entry; got: \(tags)"
        )
    }

    func testGivenLogger_whenLogIsEmitted_itCarriesDeviceAndOsBlocks() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("device-os-check")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        log.assertValue(forKeyPath: "device", isTypeOf: [String: Any].self)
        log.assertValue(forKeyPath: "os", isTypeOf: [String: Any].self)

        let deviceModel: String = try log.value(forKeyPath: "device.model")
        let deviceBrand: String = try log.value(forKeyPath: "device.brand")
        XCTAssertFalse(deviceModel.isEmpty, "device.model should be a non-empty string")
        XCTAssertFalse(deviceBrand.isEmpty, "device.brand should be a non-empty string")

        let osName: String = try log.value(forKeyPath: "os.name")
        let osVersion: String = try log.value(forKeyPath: "os.version")
        XCTAssertFalse(osName.isEmpty, "os.name should be a non-empty string")
        XCTAssertFalse(osVersion.isEmpty, "os.version should be a non-empty string")
    }

    func testGivenLogger_whenLogIsEmitted_itCarriesInternalDdBlock() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("dd-block-check")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        log.assertValue(forKeyPath: "_dd", isTypeOf: [String: Any].self)

        let architecture: String = try log.value(forKeyPath: "_dd.device.architecture")
        XCTAssertFalse(architecture.isEmpty, "_dd.device.architecture should be a non-empty string")
    }

    // MARK: - §4 Tags

    func testGivenLogger_whenTagIsAddedWithKeyValue_itPersistsAcrossSubsequentLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addTag(withKey: "feature", value: "promo")
                app.logger.info("first")
                app.logger.info("second")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")
        for log in result.logs {
            let tags: String = try log.value(forKeyPath: "ddtags")
            XCTAssertTrue(
                tags.split(separator: ",").contains("feature:promo"),
                "ddtags should contain `feature:promo` on every log emitted after addTag(...); got: \(tags)"
            )
        }
    }

    func testGivenLoggerWithTag_whenTagIsRemovedByKey_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addTag(withKey: "feature", value: "promo")
                app.logger.info("with-tag")
                app.logger.removeTag(withKey: "feature")
                app.logger.info("without-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "with-tag" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "without-tag" })

        let tagsA: String = try logA.value(forKeyPath: "ddtags")
        let tagsB: String = try logB.value(forKeyPath: "ddtags")

        XCTAssertTrue(
            tagsA.split(separator: ",").contains("feature:promo"),
            "First log emitted before removeTag(...) should still carry `feature:promo`; got: \(tagsA)"
        )
        XCTAssertFalse(
            tagsB.split(separator: ",").contains("feature:promo"),
            "Log emitted after removeTag(...) must not carry `feature:promo`; got: \(tagsB)"
        )
    }

    func testGivenLogger_whenRawTagIsAdded_itAppearsInDdTags() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.add(tag: "production")
                app.logger.info("first")
                app.logger.info("second")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")
        for log in result.logs {
            let tags: String = try log.value(forKeyPath: "ddtags")
            XCTAssertTrue(
                tags.split(separator: ",").contains("production"),
                "ddtags should contain raw tag `production` on every log emitted after add(tag:); got: \(tags)"
            )
        }
    }

    func testGivenLoggerWithRawTag_whenRawTagIsRemoved_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.add(tag: "production")
                app.logger.info("with-tag")
                app.logger.remove(tag: "production")
                app.logger.info("without-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "with-tag" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "without-tag" })

        let tagsA: String = try logA.value(forKeyPath: "ddtags")
        let tagsB: String = try logB.value(forKeyPath: "ddtags")

        XCTAssertTrue(
            tagsA.split(separator: ",").contains("production"),
            "First log emitted before remove(tag:) should still carry `production`; got: \(tagsA)"
        )
        XCTAssertFalse(
            tagsB.split(separator: ",").contains("production"),
            "Log emitted after remove(tag:) must not carry `production`; got: \(tagsB)"
        )
    }

    func testGivenLogger_whenTagContainsIllegalCharacters_eachIsReplacedWithUnderscore() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.add(tag: "weird tag!@#")
                app.logger.info("sanitized-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        XCTAssertTrue(
            tags.split(separator: ",").contains("weird_tag___"),
            "Each illegal character in the tag should be replaced one-for-one with `_`; got: \(tags)"
        )
    }

    func testGivenLogger_whenTagContainsUppercase_itIsLowercasedInDdTags() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addTag(withKey: "MyKey", value: "MyValue")
                app.logger.info("uppercase-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        XCTAssertTrue(
            tags.split(separator: ",").contains("mykey:myvalue"),
            "Tag with uppercase characters should be lowercased to `mykey:myvalue`; got: \(tags)"
        )
        XCTAssertFalse(
            tags.contains("MyKey") || tags.contains("MyValue"),
            "Original uppercase form should not appear; got: \(tags)"
        )
    }

    func testGivenLogger_whenTagExceeds200Characters_itIsTruncatedToTheFirst200() throws {
        let value = String(repeating: "a", count: 250)

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addTag(withKey: "k", value: value)
                app.logger.info("long-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        let longEntry = try XCTUnwrap(
            tags.split(separator: ",").map(String.init).first { $0.hasPrefix("k:") },
            "Expected an entry beginning with `k:` in ddtags; got: \(tags)"
        )
        let expected = "k:" + String(repeating: "a", count: 198)
        XCTAssertEqual(longEntry.count, 200, "Truncated tag length should equal Constraints.maxTagLength (200)")
        XCTAssertEqual(longEntry, expected, "Truncation should keep the first 200 characters of the joined `key:value` tag")
    }

    func testGivenLoggerWithoutUserTags_whenLogIsEmitted_ddtagsCarriesSDKManagedEntries() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK(sdkSetup: { config in
                config.env = "harness-env"
                config.service = "harness-service"
            }))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("sdk-managed-tags")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        let entries = Set(tags.split(separator: ",").map(String.init))

        XCTAssertTrue(entries.contains("env:harness-env"), "ddtags should contain `env:harness-env`; got: \(tags)")
        XCTAssertTrue(entries.contains("service:harness-service"), "ddtags should contain `service:harness-service`; got: \(tags)")

        let hasVersion = entries.contains { $0.hasPrefix("version:") && $0.count > "version:".count }
        let hasSDKVersion = entries.contains { $0.hasPrefix("sdk_version:") && $0.count > "sdk_version:".count }
        XCTAssertTrue(hasVersion, "ddtags should contain a non-empty `version:<value>` entry; got: \(tags)")
        XCTAssertTrue(hasSDKVersion, "ddtags should contain a non-empty `sdk_version:<value>` entry; got: \(tags)")
    }

    // MARK: - §5 Attributes

    func testGivenLogger_whenAttributeIsAddedWithKeyAndValue_itPersistsAcrossSubsequentLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addAttribute(forKey: "tenant", value: "acme")
                app.logger.info("first")
                app.logger.info("second")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")
        for log in result.logs {
            let tenant: String = try log.value(forKeyPath: "tenant")
            XCTAssertEqual(tenant, "acme", "Logger-scoped attribute should appear on every subsequent log")
        }
    }

    func testGivenLoggerWithAttribute_whenAttributeIsRemovedByKey_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addAttribute(forKey: "tenant", value: "acme")
                app.logger.info("with-attr")
                app.logger.removeAttribute(forKey: "tenant")
                app.logger.info("without-attr")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "with-attr" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "without-attr" })

        let tenantOnA: String? = try logA.valueOrNil(forKeyPath: "tenant")
        let tenantOnB: String? = try logB.valueOrNil(forKeyPath: "tenant")

        XCTAssertEqual(tenantOnA, "acme", "First log emitted before removeAttribute(...) should still carry `tenant`")
        XCTAssertNil(tenantOnB, "Log emitted after removeAttribute(...) must not carry `tenant`")
    }

    func testGivenLogsFeatureEnabled_whenGlobalAttributeIsAdded_allLoggersIncludeItOnSubsequentLogs() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.loggers["a"] = Logger.create(with: Logger.Configuration(name: "logger-a"), in: app.core)
                app.loggers["b"] = Logger.create(with: Logger.Configuration(name: "logger-b"), in: app.core)
            }
            .when { app in
                Logs.addAttribute(forKey: "global", value: "shared", in: app.core)
                app.loggers["a"]?.info("from a")
                app.loggers["b"]?.info("from b")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")
        for log in result.logs {
            let global: String = try log.value(forKeyPath: "global")
            XCTAssertEqual(global, "shared", "Global attribute should appear on every logger's subsequent logs")
        }
    }

    func testGivenGlobalAttribute_whenGlobalAttributeIsRemoved_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
            }
            .when { app in
                Logs.addAttribute(forKey: "global", value: "shared", in: app.core)
                app.logger.info("with-global")
                Logs.removeAttribute(forKey: "global", in: app.core)
                app.logger.info("without-global")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "with-global" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "without-global" })

        let globalOnA: String? = try logA.valueOrNil(forKeyPath: "global")
        let globalOnB: String? = try logB.valueOrNil(forKeyPath: "global")

        XCTAssertEqual(globalOnA, "shared", "Log emitted before global removeAttribute(...) should still carry `global`")
        XCTAssertNil(globalOnB, "Log emitted after global removeAttribute(...) must not carry `global`")
    }

    func testGivenLoggerWithAttribute_whenSameKeyIsPassedPerLog_perLogValueWins() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addAttribute(forKey: "k", value: "logger-val")
                app.logger.info("with-override", attributes: ["k": "per-log-val"])
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let value: String = try result.logs[0].value(forKeyPath: "k")
        XCTAssertEqual(value, "per-log-val", "Per-log attribute value should override the logger-scoped value for this log")
    }

    func testGivenLogger_whenAttributeIsPassedPerLog_subsequentLogsDoNotCarryIt() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("with-per-log", attributes: ["k": "v"])
                app.logger.info("without-per-log")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 2, "Two logs should be recorded")

        let logA = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "with-per-log" })
        let logB = try XCTUnwrap(result.logs.first { (try? $0.value(forKeyPath: "message") as String) == "without-per-log" })

        let kOnA: String? = try logA.valueOrNil(forKeyPath: "k")
        let kOnB: String? = try logB.valueOrNil(forKeyPath: "k")

        XCTAssertEqual(kOnA, "v", "First log should carry the per-log attribute")
        XCTAssertNil(kOnB, "Second log without the per-log attribute must not carry `k`")
    }

    func testGivenAttributeAtAllThreeScopes_whenLogIsEmitted_perLogValueWinsOverLoggerAndGlobal() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .and { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
            }
            .when { app in
                // Set the same key `k` at every scope, with distinct values.
                Logs.addAttribute(forKey: "k", value: "global-val", in: app.core)
                app.logger.addAttribute(forKey: "k", value: "logger-val")
                app.logger.info("precedence", attributes: ["k": "per-log-val"])
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let value: String = try result.logs[0].value(forKeyPath: "k")
        XCTAssertEqual(value, "per-log-val", "Per-log attribute should win over logger-scoped and global values")
    }

    func testGivenAttributeWithDottedKey_whenLogIsEmitted_keyAppearsAsFlatLiteralKeyInJson() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addAttribute(forKey: "user.profile.id", value: 42)
                app.logger.info("dotted-key")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        let id: Int = try log.value(forKeyPath: "user.profile.id")
        XCTAssertEqual(id, 42, "Dotted-key attribute should be retrievable at `user.profile.id`")

        let userPrefix: [String: Any]? = try log.valueOrNil(forKeyPath: "user")
        XCTAssertNil(userPrefix, "Encoder should produce a flat literal key `user.profile.id`, not a nested `user` object")
    }

    func testGivenAttributesOfVariousEncodableTypes_whenLogIsEmitted_eachTypeRoundtripsCleanly() throws {
        struct Profile: Encodable {
            let name: String
            let age: Int
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let expectedDateString = iso8601DateFormatter.string(from: date)
        let profile = Profile(name: "alice", age: 30)
        let nested: [String: AnyEncodable] = [
            "count": AnyEncodable(3),
            "label": AnyEncodable("ok"),
            "active": AnyEncodable(true)
        ]

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.addAttribute(forKey: "intAttr", value: 7)
                app.logger.addAttribute(forKey: "stringAttr", value: "hello")
                app.logger.addAttribute(forKey: "boolAttr", value: true)
                app.logger.addAttribute(forKey: "dateAttr", value: date)
                app.logger.addAttribute(forKey: "profileAttr", value: profile)
                app.logger.addAttribute(forKey: "nestedAttr", value: nested)
                app.logger.info("encodable-types")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        // Int → JSON number, retrievable as Int (and not as String).
        let intValue: Int = try log.value(forKeyPath: "intAttr")
        XCTAssertEqual(intValue, 7)

        // String → JSON string.
        let stringValue: String = try log.value(forKeyPath: "stringAttr")
        XCTAssertEqual(stringValue, "hello")

        // Bool → JSON bool.
        let boolValue: Bool = try log.value(forKeyPath: "boolAttr")
        XCTAssertTrue(boolValue)

        // Date → ISO8601 string (custom strategy in `JSONEncoder.dd.default()`).
        let dateValue: String = try log.value(forKeyPath: "dateAttr")
        XCTAssertEqual(dateValue, expectedDateString, "Date should encode as ISO8601 with fractional seconds")

        // Custom `Encodable` struct → JSON object with the struct's fields preserved.
        let profileName: String = try log.value(forKeyPath: "profileAttr.name")
        let profileAge: Int = try log.value(forKeyPath: "profileAttr.age")
        XCTAssertEqual(profileName, "alice")
        XCTAssertEqual(profileAge, 30)

        // Nested `[String: Any]` with mixed values — each value preserves its JSON type.
        let nestedCount: Int = try log.value(forKeyPath: "nestedAttr.count")
        let nestedLabel: String = try log.value(forKeyPath: "nestedAttr.label")
        let nestedActive: Bool = try log.value(forKeyPath: "nestedAttr.active")
        XCTAssertEqual(nestedCount, 3)
        XCTAssertEqual(nestedLabel, "ok")
        XCTAssertTrue(nestedActive)
    }

    // MARK: - §6 Errors

    func testGivenSwiftErrorPassedToLogger_whenLogIsEmitted_errorKindMatchesSwiftErrorTypeName() throws {
        struct CheckoutFailed: Error {}

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.error("checkout error", error: CheckoutFailed())
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let kind: String = try result.logs[0].value(forKeyPath: "error.kind")
        XCTAssertEqual(kind, "CheckoutFailed", "error.kind should equal the Swift Error type name")
    }

    func testGivenSwiftErrorWithCustomDescription_whenLogIsEmitted_errorMessageMatchesStringDescription() throws {
        struct PaymentRejected: Error, CustomStringConvertible {
            let description: String = "card declined: insufficient_funds"
        }

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.error("payment error", error: PaymentRejected())
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let message: String = try result.logs[0].value(forKeyPath: "error.message")
        XCTAssertEqual(
            message,
            "card declined: insufficient_funds",
            "error.message should equal `String(describing: error)` (via `\\(error)`), which uses `CustomStringConvertible.description` when present"
        )
    }

    func testGivenSwiftErrorPassedToLogger_whenLogIsEmitted_errorStackEqualsErrorDescription() throws {
        struct StackProbe: Error, CustomStringConvertible {
            let description: String = "boom-marker-3173"
        }

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.error("stack-check", error: StackProbe())
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let stack: String = try result.logs[0].value(forKeyPath: "error.stack")
        let message: String = try result.logs[0].value(forKeyPath: "error.message")
        XCTAssertFalse(stack.isEmpty, "error.stack should be a non-empty string")
        XCTAssertEqual(stack, "boom-marker-3173", "error.stack mirrors `String(describing: error)` for Swift Errors")
        XCTAssertEqual(stack, message, "error.stack and error.message are populated from the same source for Swift Errors")
    }

    func testGivenAnySwiftErrorPassedToLogger_whenLogIsEmitted_errorSourceTypeIsIos() throws {
        struct AnyError: Error {}

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.error("source-type-check", error: AnyError())
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let sourceType: String = try result.logs[0].value(forKeyPath: "error.source_type")
        XCTAssertEqual(sourceType, "ios", "error.source_type must always be `ios` for errors emitted from this SDK")
    }

    func testGivenErrorLogWithFingerprintAttribute_whenLogIsEmitted_errorFingerprintIsPopulated() throws {
        struct AnyError: Error {}

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.error(
                    "fingerprint-check",
                    error: AnyError(),
                    attributes: [Logs.Attributes.errorFingerprint: "my-custom-fingerprint"]
                )
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let fingerprint: String = try result.logs[0].value(forKeyPath: "error.fingerprint")
        XCTAssertEqual(fingerprint, "my-custom-fingerprint", "Per-log `Logs.Attributes.errorFingerprint` should populate `error.fingerprint`")

        let leaked: String? = try result.logs[0].valueOrNil(forKeyPath: Logs.Attributes.errorFingerprint)
        XCTAssertNil(leaked, "`_dd.error.fingerprint` should be consumed and not appear as a user attribute on the log JSON")
    }

    func testGivenLogWithoutErrorParameter_whenLogIsEmitted_noErrorFieldsArePresent() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("no-error-log")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        log.assertNoValue(forKey: "error.kind")
        log.assertNoValue(forKey: "error.message")
        log.assertNoValue(forKey: "error.stack")
        log.assertNoValue(forKey: "error.source_type")
        log.assertNoValue(forKey: "error.fingerprint")
        log.assertNoValue(forKey: "error.binary_images")
    }

    func testGivenCriticalLogWithError_whenLogIsEmitted_errorFieldsArePopulatedAndBinaryImagesAreAbsentInHarness() throws {
        struct FatalFailure: Error, CustomStringConvertible {
            let description: String = "system_failure"
        }

        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.critical(
                    "critical-error",
                    error: FatalFailure(),
                    attributes: [CrossPlatformAttributes.includeBinaryImages: true]
                )
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let log = result.logs[0]

        log.assertStatus(equals: "critical")

        let kind: String = try log.value(forKeyPath: "error.kind")
        let message: String = try log.value(forKeyPath: "error.message")
        let stack: String = try log.value(forKeyPath: "error.stack")
        let sourceType: String = try log.value(forKeyPath: "error.source_type")
        XCTAssertEqual(kind, "FatalFailure")
        XCTAssertEqual(message, "system_failure")
        XCTAssertEqual(stack, "system_failure")
        XCTAssertEqual(sourceType, "ios")

        log.assertNoValue(forKey: "error.binary_images")
    }
}
