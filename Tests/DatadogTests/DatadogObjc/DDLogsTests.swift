/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogLogs
@testable import Datadog
@testable import DatadogObjc

// swiftlint:disable multiline_arguments_brackets
// swiftlint:disable compiler_protocol_init
class DDLogsTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
    }

    override func tearDown() {
        CoreRegistry.unregisterDefault()
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testDefaultConfiguration() {
        // Given
        let config = DDLogsConfiguration()

        // Then
        XCTAssertEqual(config.configuration.samplingRate, 100)
        XCTAssertNil(config.configuration.customIntakeURL)
        XCTAssertTrue(config.configuration.bundle === Bundle.main)
        XCTAssertTrue(config.configuration.processInfo === ProcessInfo.processInfo)
    }

    func testConfigurationOverrides() throws {
        // Given
        let samplingRate: Float = .random(in: 0...100)
        let customIntakeURL: URL = .mockRandom()
        let bundleIdentifier: String = .mockRandom()

        // When
        DDLogs.enable(
            with: DDLogsConfiguration(
                samplingRate: samplingRate,
                customIntakeURL: customIntakeURL,
                bundle: .mockWith(bundleIdentifier: bundleIdentifier)
            )
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        let requestBuilder = try XCTUnwrap(logs.requestBuilder as? RequestBuilder)
        XCTAssertEqual(logs.applicationBundleIdentifier, bundleIdentifier)
        XCTAssertEqual(logs.sampler.samplingRate, samplingRate)
        XCTAssertEqual(requestBuilder.customIntakeURL, customIntakeURL)
    }

    func testConfiguration_withDebug_itDisableSampling() throws {
        // When
        DDLogs.enable(
            with: DDLogsConfiguration(
                samplingRate: 0,
                processInfo: ProcessInfoMock(arguments: [LaunchArguments.Debug])
            )
        )

        // Then
        let logs = try XCTUnwrap(core.get(feature: LogsFeature.self))
        XCTAssertEqual(logs.sampler.samplingRate, 100)
    }

    func testSendingLogsWithDifferentLevels() throws {
        let feature: LogsFeature = .mockAny()
        try CoreRegistry.default.register(feature: feature)

        let objcLogger = DDLogger.builder().build()

        objcLogger.debug("message")
        objcLogger.info("message")
        objcLogger.notice("message")
        objcLogger.warn("message")
        objcLogger.error("message")
        objcLogger.critical("message")

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
    }

    func testSendingNSError() throws {
        let feature: LogsFeature = .mockAny()
        try CoreRegistry.default.register(feature: feature)

        let objcLogger = DDLogger.builder().build()

        let error = NSError(domain: "UnitTest", code: 11_235, userInfo: [NSLocalizedDescriptionKey: "UnitTest error"])

        objcLogger.debug("message", error: error, attributes: [:])
        objcLogger.info("message", error: error, attributes: [:])
        objcLogger.notice("message", error: error, attributes: [:])
        objcLogger.warn("message", error: error, attributes: [:])
        objcLogger.error("message", error: error, attributes: [:])
        objcLogger.critical("message", error: error, attributes: [:])

        let logMatchers = try core.waitAndReturnLogMatchers()
        for matcher in logMatchers {
            matcher.assertValue(
                forKeyPath: "error.stack",
                equals: "Error Domain=UnitTest Code=11235 \"UnitTest error\" UserInfo={NSLocalizedDescription=UnitTest error}"
            )
            matcher.assertValue(
                forKeyPath: "error.message",
                equals: "UnitTest error"
            )
            matcher.assertValue(
                forKeyPath: "error.kind",
                equals: "UnitTest - 11235"
            )
        }
    }

    func testSendingMessageAttributes() throws {
        let feature: LogsFeature = .mockAny()
        try CoreRegistry.default.register(feature: feature)

        let objcLogger = DDLogger.builder().build()

        objcLogger.debug("message", attributes: ["foo": "bar"])
        objcLogger.info("message", attributes: ["foo": "bar"])
        objcLogger.notice("message", attributes: ["foo": "bar"])
        objcLogger.warn("message", attributes: ["foo": "bar"])
        objcLogger.error("message", attributes: ["foo": "bar"])
        objcLogger.critical("message", attributes: ["foo": "bar"])

        let logMatchers = try core.waitAndReturnLogMatchers()
        logMatchers[0].assertStatus(equals: "debug")
        logMatchers[1].assertStatus(equals: "info")
        logMatchers[2].assertStatus(equals: "notice")
        logMatchers[3].assertStatus(equals: "warn")
        logMatchers[4].assertStatus(equals: "error")
        logMatchers[5].assertStatus(equals: "critical")
        logMatchers.forEach { matcher in
            matcher.assertAttributes(equal: ["foo": "bar"])
        }
    }

    func testSendingLoggerAttributes() throws {
        let feature: LogsFeature = .mockAny()
        try CoreRegistry.default.register(feature: feature)

        let objcLogger = DDLogger.builder().build()

        objcLogger.addAttribute(forKey: "nsstring", value: NSString(string: "hello"))
        objcLogger.addAttribute(forKey: "nsbool", value: NSNumber(booleanLiteral: true))
        objcLogger.addAttribute(forKey: "nsint", value: NSInteger(integerLiteral: 10))
        objcLogger.addAttribute(forKey: "nsnumber", value: NSNumber(value: 10.5))
        objcLogger.addAttribute(forKey: "nsnull", value: NSNull())
        objcLogger.addAttribute(forKey: "nsurl", value: NSURL(string: "http://apple.com")!)
        objcLogger.addAttribute(
            forKey: "nsarray-of-int",
            value: NSArray(array: [1, 2, 3])
        )
        objcLogger.addAttribute(
            forKey: "nsdictionary-of-date",
            value: NSDictionary(dictionary: [
                "date1": Date.mockDecember15th2019At10AMUTC(),
                "date2": Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 60 * 60)
            ])
        )
        objcLogger.info("message")

        let logMatcher = try core.waitAndReturnLogMatchers()[0]
        logMatcher.assertValue(forKey: "nsstring", equals: "hello")
        logMatcher.assertValue(forKey: "nsbool", equals: true)
        logMatcher.assertValue(forKey: "nsint", equals: 10)
        logMatcher.assertValue(forKey: "nsnumber", equals: 10.5)
        logMatcher.assertValue(forKeyPath: "nsnull", isTypeOf: Optional<Any>.self)
        logMatcher.assertValue(forKey: "nsurl", equals: "http://apple.com")
        logMatcher.assertValue(forKey: "nsarray-of-int", equals: [1, 2, 3])
        logMatcher.assertValue(forKeyPath: "nsdictionary-of-date.date1", equals: "2019-12-15T10:00:00.000Z")
        logMatcher.assertValue(forKeyPath: "nsdictionary-of-date.date2", equals: "2019-12-15T11:00:00.000Z")
    }

    func testSettingTagsAndAttributes() throws {
        core.context = .mockWith(
            env: "test",
            version: "1.2.3"
        )

        let feature: LogsFeature = .mockAny()
        try CoreRegistry.default.register(feature: feature)

        let objcLogger = DDLogger.builder().build()

        objcLogger.addAttribute(forKey: "foo", value: "bar")
        objcLogger.addAttribute(forKey: "bizz", value: "buzz")
        objcLogger.removeAttribute(forKey: "bizz")

        objcLogger.addTag(withKey: "foo", value: "bar")
        objcLogger.addTag(withKey: "bizz", value: "buzz")
        objcLogger.removeTag(withKey: "bizz")

        objcLogger.add(tag: "foobar")
        objcLogger.add(tag: "bizzbuzz")
        objcLogger.remove(tag: "bizzbuzz")

        objcLogger.info(.mockAny())

        let logMatcher = try core.waitAndReturnLogMatchers()[0]
        logMatcher.assertValue(forKeyPath: "foo", equals: "bar")
        logMatcher.assertNoValue(forKey: "bizz")
        logMatcher.assertTags(equal: ["foo:bar", "foobar", "env:test", "version:1.2.3"])
    }
}
// swiftlint:enable multiline_arguments_brackets
// swiftlint:enable compiler_protocol_init
