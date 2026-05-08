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

    /// Each log level maps to matching status — for each of `debug`, `info`, `notice`,
    /// `warn`, `error`, `critical`, the recorded log carries the matching `status` string,
    /// in the same order as emitted.
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

    /// Base `log(level:message:error:attributes:)` method — emitting via the protocol-level
    /// method produces output indistinguishable from convenience methods. We compare two
    /// loggers' outputs side-by-side: one emitting via `info("x")`, the other via
    /// `log(level: .info, message: "x", error: nil, attributes: nil)`.
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

        // Same SDK-managed fields — service, logger.version, ddtags. The recorded JSON does
        // not have a top-level `env` key (it lives only inside `ddtags`), so we compare the
        // tag string instead.
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

    /// Info log emission — `info("user signed in")` produces a single recorded log
    /// with status `"info"` and matching message.
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

    /// Message text preserved verbatim — special characters, unicode, multi-line content
    /// survive end-to-end. The exact bytes emitted should be present in the recorded log
    /// `message` field.
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

    /// `threadName` populated — log emitted while `Thread.current.name` is set carries
    /// that name in `logger.thread_name`. `RemoteLogger` collects the thread name
    /// synchronously on the user thread (see `RemoteLogger.internalLog`), so setting
    /// the main thread's name immediately before emission is sufficient and avoids
    /// any cross-thread synchronization concerns.
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

    /// `applicationVersion` and `applicationBuildNumber` — populated from bundle context
    /// on every log via top-level `version` and `build_version` fields. The harness uses
    /// `Bundle.main` (the test runner bundle) by default, so we assert that both values
    /// are non-empty strings rather than pinning to specific values which depend on the
    /// runner's Info.plist.
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

    /// `build_id` field handling — `build_id` is set only via the cross-platform
    /// `additionalConfiguration[CrossPlatformAttributes.buildId]` path (see `Datadog.swift`).
    /// The harness does not populate this attribute, so the field is expected to be
    /// absent from the recorded JSON payload. This test asserts that absence — if the SDK
    /// ever starts auto-deriving `build_id` for the binary, both shapes (present
    /// non-empty / absent) are valid and the test should be relaxed accordingly.
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

    /// `environment` populated from `Datadog.Configuration.env` — the env value passed
    /// to `Datadog.initialize(...)` propagates to every log. The encoder does not emit a
    /// top-level `env` field; instead, env appears as the `env:<value>` entry in the
    /// `ddtags` string (see `LogEventSanitizer` SDK-managed tag list and
    /// `LogEventEncoder` which only writes `ddtags`).
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

    /// `device` and `os` blocks present — every log carries `device` and `os` JSON objects
    /// describing the simulated environment. We assert presence and non-emptiness on the
    /// most stable sub-keys (`device.model`, `device.brand`, `os.name`, `os.version`)
    /// rather than pinning specific values, which can shift between simulator and host.
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

    /// `_dd` internal block present — every log JSON carries a `_dd` object with internal
    /// SDK metadata. Minimum assertion: `_dd` is present as a JSON object. Currently the
    /// SDK populates `_dd.device.architecture` (see `LogEvent.Dd`); we assert that nested
    /// field as a stronger shape check.
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

    /// `addTag(withKey:value:)` persists — a tag added once is visible on every subsequent
    /// log emitted by the same logger. Encoded as the `key:value` entry in `ddtags` (which
    /// is a comma-separated string composed of user tags + SDK-managed `ddTags`).
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

    /// `removeTag(withKey:)` — once a tag is removed, it disappears from subsequent logs;
    /// logs already emitted while the tag was set keep it (recorded payloads are immutable).
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

    /// `add(tag:)` raw tag — a value-only tag (no `key:value` colon) appears verbatim in
    /// `ddtags` of subsequent logs.
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

    /// `remove(tag:)` raw tag — once a raw tag is removed, it disappears from subsequent
    /// logs while logs emitted while it was set keep it.
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

    /// Tag sanitization — special characters. `LogEventSanitizer` lowercases the tag, then
    /// replaces every character outside `[a-z0-9_:./-]` with `_` (regex
    /// `[^a-z0-9_:.\/-]`, see `LogEventSanitizer.replaceIllegalCharactersIn`). Special
    /// characters in either key or value are individually replaced with underscores.
    func testGivenLogger_whenTagContainsIllegalCharacters_eachIsReplacedWithUnderscore() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                // Spaces, `!`, `@`, `#` are all outside `[a-z0-9_:./-]` and should be
                // each replaced with `_` (one-for-one substitution, not collapsed).
                app.logger.add(tag: "weird tag!@#")
                app.logger.info("sanitized-tag")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1, "Exactly one log should be recorded")
        let tags: String = try result.logs[0].value(forKeyPath: "ddtags")
        // "weird tag!@#" (12 chars) → lowercase → unchanged
        // → each illegal char (' ' at idx 5, '!' at 9, '@' at 10, '#' at 11) → '_'
        // → "weird_tag___" (still 12 chars: 5 letters + 1 underscore + 3 letters + 3 underscores)
        XCTAssertTrue(
            tags.split(separator: ",").contains("weird_tag___"),
            "Each illegal character in the tag should be replaced one-for-one with `_`; got: \(tags)"
        )
    }

    /// Tag sanitization — uppercase characters. `LogEventSanitizer` lowercases every tag
    /// before any other sanitization step (see `sanitize(tags:).map { $0.lowercased() }`),
    /// so an uppercase `key:value` pair is normalised to lowercase end-to-end.
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

    /// Tag truncation at 200 characters. `LogEventSanitizer.limitToMaxLength` truncates
    /// the *whole tag* (the joined `"key:value"` string, not just the value) when its
    /// length exceeds `Constraints.maxTagLength = 200`. With `key="k"` and a 250-char
    /// value, the full tag is 252 chars; the recorded entry should be exactly 200 chars
    /// — `"k:"` plus the first 198 chars of the value.
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

    /// SDK-managed tags always present — even with no user tags, `ddtags` carries the
    /// SDK-managed entries assembled by `DatadogContext.buildDDTags()`:
    /// `service:<value>`, `version:<value>`, `sdk_version:<value>`, `env:<value>`
    /// (plus optional `variant:<value>` when set). Note the SCENARIOS.md description
    /// mentions `host`/`device`/`source` — those are *reserved* tag keys (the sanitizer
    /// drops user tags using them) but the SDK does not auto-emit them; only the four
    /// fields above are unconditionally injected by the core.
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

        // `version` and `sdk_version` are always present; their values come from bundle
        // / SDK constants and are non-empty but not pinned here.
        let hasVersion = entries.contains { $0.hasPrefix("version:") && $0.count > "version:".count }
        let hasSDKVersion = entries.contains { $0.hasPrefix("sdk_version:") && $0.count > "sdk_version:".count }
        XCTAssertTrue(hasVersion, "ddtags should contain a non-empty `version:<value>` entry; got: \(tags)")
        XCTAssertTrue(hasSDKVersion, "ddtags should contain a non-empty `sdk_version:<value>` entry; got: \(tags)")
    }

    // §4 "Two loggers — tag isolation" is covered by
    // `LogsConfigTests.testGivenTwoLoggers_whenTagIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs()`
    // (added in Batch 2 for §2 "Multiple named loggers — independent tag state").
}
