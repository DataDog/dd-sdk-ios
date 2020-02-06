import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    private let appContextMock = AppContext(
        bundleIdentifier: "com.datadoghq.ios-sdk",
        bundleVersion: "1.0.0",
        bundleShortVersion: "1.0.0"
    )
    private let userInfoProviderMock: UserInfoProvider = .mockWith(
        userInfo: UserInfo(id: "abc-123", name: "Foo", email: "foo@example.com")
    )
    private let dateProviderMock = RelativeDateProvider(
        startingFrom: .mockDecember15th2019At10AMUTC(),
        advancingBySeconds: 1
    )

    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Sending logs

    func testSendingLogWithDefaultLogger() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                try logMatcher.assertItFullyMatches(jsonString: """
                {
                  "status" : "DEBUG",
                  "message" : "message",
                  "service" : "ios",
                  "logger.name" : "com.datadoghq.ios-sdk",
                  "logger.version": "\(sdkVersion)",
                  "logger.thread_name" : "main",
                  "date" : "2019-12-15T10:00:00Z",
                  "application.version": "1.0.0"
                }
                """)
            }
            .destroy()
    }

    func testSendingLogWithCustomizedLogger() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder
                    .set(serviceName: "custom-service-name")
                    .set(loggerName: "custom-logger-name")
                    .build()
                logger.debug("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                try logMatcher.assertItFullyMatches(jsonString: """
                {
                  "status" : "DEBUG",
                  "message" : "message",
                  "service" : "custom-service-name",
                  "logger.name" : "custom-logger-name",
                  "logger.version": "\(sdkVersion)",
                  "logger.thread_name" : "main",
                  "date" : "2019-12-15T10:00:00Z",
                  "application.version": "1.0.0"
                }
                """)
            }
            .destroy()
    }

    func testSendingLogsWithDifferentLevels() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder.build()
                logger.debug("message")
                logger.info("message")
                logger.notice("message")
                logger.warn("message")
                logger.error("message")
                logger.critical("message")
            }
            .waitUntil(numberOfLogsSent: 6)
            .verifyAll { logMatchers in
                logMatchers[0].assertStatus(equals: "DEBUG")
                logMatchers[1].assertStatus(equals: "INFO")
                logMatchers[2].assertStatus(equals: "NOTICE")
                logMatchers[3].assertStatus(equals: "WARN")
                logMatchers[4].assertStatus(equals: "ERROR")
                logMatchers[5].assertStatus(equals: "CRITICAL")
            }
            .destroy()
    }

    // MARK: - Sending attributes

    func testSendingLoggerAttributesOfDifferentEncodableValues() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // string literal
                logger.addAttribute(forKey: "string", value: "hello")

                // boolean literal
                logger.addAttribute(forKey: "bool", value: true)

                // integer literal
                logger.addAttribute(forKey: "int", value: 10)

                // Typed 8-bit unsigned Integer
                logger.addAttribute(forKey: "uint-8", value: UInt8(10))

                // double-precision, floating-point value
                logger.addAttribute(forKey: "double", value: 10.5)

                // array of `Encodable` integer
                logger.addAttribute(forKey: "array-of-int", value: [1, 2, 3])

                // dictionary of `Encodable` date types
                logger.addAttribute(forKey: "dictionary-of-date", value: [
                    "date1": Date.mockDecember15th2019At10AMUTC(),
                    "date2": Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 60 * 60)
                ])

                struct Person: Codable {
                    let name: String
                    let age: Int
                    let nationality: String
                }

                // custom `Encodable` structure
                logger.addAttribute(forKey: "person", value: Person(name: "Adam", age: 30, nationality: "Polish"))

                // nested string literal
                logger.addAttribute(forKey: "nested.string", value: "hello")

                logger.info("message")
            }
            .waitUntil(numberOfLogsSent: 1)
            .verifyFirst { logMatcher in
                try logMatcher.assertItFullyMatches(jsonString: """
                {
                  "status" : "INFO",
                  "message" : "message",
                  "service" : "ios",
                  "logger.name" : "com.datadoghq.ios-sdk",
                  "logger.version": "\(sdkVersion)",
                  "logger.thread_name" : "main",
                  "date" : "2019-12-15T10:00:00Z",
                  "application.version": "1.0.0",
                  "string" : "hello",
                  "bool" : true,
                  "int" : 10,
                  "uint-8" : 10,
                  "double" : 10.5,
                  "array-of-int" : [1, 2, 3],
                  "dictionary-of-date" : {
                     "date1": "2019-12-15T10:00:00Z",
                     "date2": "2019-12-15T11:00:00Z"
                  },
                  "person" : {
                     "name" : "Adam",
                     "age" : 30,
                     "nationality" : "Polish",
                  },
                  "nested.string" : "hello"
                }
                """)
            }
            .destroy()
    }

    func testSendingMessageAttributes() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // add logger attribute
                logger.addAttribute(forKey: "attribute", value: "logger's value")

                // send message with no attributes
                logger.info("info message 1")

                // send message with attribute overriding logger's attribute
                logger.info("info message 2", attributes: ["attribute": "message's value"])

                // remove logger attribute
                logger.removeAttribute(forKey: "attribute")

                // send message
                logger.info("info message 3")
            }
            .waitUntil(numberOfLogsSent: 3)
            .verifyAll { logMatchers in
                logMatchers[0].assertValue(forKey: "attribute", equals: "logger's value")
                logMatchers[1].assertValue(forKey: "attribute", equals: "message's value")
                logMatchers[2].assertNoValue(forKey: "attribute")
            }
            .destroy()
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        try DatadogInstanceMock.build
            .with(appContext: appContextMock)
            .with(dateProvider: dateProviderMock)
            .initialize()
            .run {
                let logger = Logger.builder.build()

                // add tag
                logger.add(tag: "tag1")

                // send message
                logger.info("info message 1")

                // add tag with key
                logger.addTag(withKey: "tag2", value: "abcd")

                // send message
                logger.info("info message 2")

                // remove tag with key
                logger.removeTag(withKey: "tag2")

                // remove tag
                logger.remove(tag: "tag1")

                // send message
                logger.info("info message 3")
            }
            .waitUntil(numberOfLogsSent: 3)
            .verifyAll { logMatchers in
                logMatchers[0].assertTags(equal: ["tag1"])
                logMatchers[1].assertTags(equal: ["tag1", "tag2:abcd"])
                logMatchers[2].assertNoValue(forKey: LogEncoder.StaticCodingKeys.tags.rawValue)
            }
            .destroy()
    }

    // MARK: - Customizing outputs

    func testUsingDifferentOutputs() throws {
        Datadog.instance = .mockAny()

        assertThat(
            logger: Logger.builder.build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).build(),
            usesOutput: NoOpLogOutput.self
        )
        assertThat(
            logger: Logger.builder.printLogsToConsole(true).build(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(true).build(),
            usesCombinedOutputs: [LogFileOutput.self, LogConsoleOutput.self]
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(true).build(),
            usesOutput: LogConsoleOutput.self
        )
        assertThat(
            logger: Logger.builder.printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(true).printLogsToConsole(false).build(),
            usesOutput: LogFileOutput.self
        )
        assertThat(
            logger: Logger.builder.sendLogsToDatadog(false).printLogsToConsole(false).build(),
            usesOutput: NoOpLogOutput.self
        )

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Initialization

    func testWhenDatadogIsNotInitialized_itThrowsProgrammerError() {
        XCTAssertThrowsError(try Logger.builder.buildOrThrow()) { error in
            XCTAssertEqual(
                (error as? ProgrammerError)?.description,
                "Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
            )
        }
    }

    // MARK: - Helpers

    private func assertThat(logger: Logger, usesOutput outputType: LogOutput.Type, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(type(of: logger.logOutput) == outputType, file: file, line: line)
    }

    private func assertThat(logger: Logger, usesCombinedOutputs outputTypes: [LogOutput.Type], file: StaticString = #file, line: UInt = #line) {
        if let combinedOutputs = (logger.logOutput as? CombinedLogOutput)?.combinedOutputs {
            XCTAssertEqual(outputTypes.count, combinedOutputs.count, file: file, line: line)
            outputTypes.forEach { outputType in
                XCTAssertTrue(combinedOutputs.contains { type(of: $0) == outputType }, file: file, line: line)
            }
        } else {
            XCTFail(file: file, line: line)
        }
    }
}
