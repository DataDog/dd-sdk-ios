import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    /// Provides consecutive `date` values for logs send with `Logger`.
    private let logDatesProvider = RelativeDateProvider(
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

    func testSendingLogsWithDefaultLogger() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 6) {
            let logger = Logger.builder.build()

            logger.debug("message")
            logger.info("message")
            logger.notice("message")
            logger.warn("message")
            logger.error("message")
            logger.critical("message")
        }

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        assertThat(jsonArrayData: requestsData[0], fullyMatches: """
        [{
          "status" : "DEBUG",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:00Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[1], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:01Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[2], fullyMatches: """
        [{
          "status" : "NOTICE",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:02Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[3], fullyMatches: """
        [{
          "status" : "WARN",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:03Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[4], fullyMatches: """
        [{
          "status" : "ERROR",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:04Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[5], fullyMatches: """
        [{
          "status" : "CRITICAL",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:05Z"
        }]
        """)
    }

    func testSendingLogsWithCustomizedLogger() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 6) {
            let logger = Logger.builder
                .set(serviceName: "custom-service-name")
                .set(loggerName: "custom-logger-name")
                .build()

            logger.debug("message")
            logger.info("message")
            logger.notice("message")
            logger.warn("message")
            logger.error("message")
            logger.critical("message")
        }

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        requestsData.forEach { requestData in
            assertThat(
                jsonArrayData: requestData,
                matchesValue: ["custom-service-name"],
                onKeyPath: "@unionOfObjects.service"
            )
            assertThat(
                jsonArrayData: requestData,
                matchesValue: ["custom-logger-name"],
                onKeyPath: "@unionOfObjects.logger.name"
            )
        }
    }

    // MARK: - Sending attributes

    func testSendingLoggerAttributesOfDifferentEncodableValues() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 1) {
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

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        assertThat(jsonArrayData: requestsData[0], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "message",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:00Z",
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
        }]
        """)
    }

    func testSendingMessageAttributes() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 3) {
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

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        assertThat(jsonArrayData: requestsData[0], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "info message 1",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:00Z",
          "attribute": "logger's value"
        }]
        """)
        assertThat(jsonArrayData: requestsData[1], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "info message 2",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:01Z",
          "attribute": "message's value"
        }]
        """)
        assertThat(jsonArrayData: requestsData[2], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "info message 3",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:02Z"
        }]
        """)
    }

    // MARK: - Sending tags

    func testSendingTags() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 3) {
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

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        assertThat(jsonArrayData: requestsData[0], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "info message 1",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:00Z",
          "ddtags": "tag1"
        }]
        """)
        assertThat(
            jsonArrayData: requestsData[1],
            matchesAnyOfTheValues: [["tag1,tag2:abcd"], ["tag2:abcd,tag1"]],
            onKeyPath: "ddtags"
        )
        assertThat(jsonArrayData: requestsData[2], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "info message 3",
          "service" : "ios",
          "logger.name" : "com.apple.dt.xctest.tool",
          "date" : "2019-12-15T10:00:02Z"
        }]
        """)
    }

    // MARK: - Customizing outputs

    func testUsingDifferentOutputs() throws {
        Datadog.instance = .mockAny(logsDirectory: temporaryDirectory)

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
}

// MARK: - Helpers for ensuring `Logger` run environment

private extension LoggerTests {
    /// Ensures that `Logger` is accessed within configured `Datadog` environment.
    private func setUpDatadogAndRecordSendingOneLogPerRequest(
        expectedRequestsCount: Int,
        run test: () -> Void
    ) throws -> RequestsRecorder {
        let requestsRecorder = RequestsRecorder()
        let expectation = self.expectation(description: "Send \(expectedRequestsCount) requests")
        expectation.expectedFulfillmentCount = expectedRequestsCount

        let logsUploadInterval: TimeInterval = 0.05 // pretty quick 😎

        let fileCreationDatesProvider = RelativeDateProvider(
            startingFrom: .mockDecember15th2019At10AMUTC(),
            advancingBySeconds: 1
        )

        // Configure `Datadog` instance
        Datadog.instance = .mockSuccessfullySendingOneLogPerRequest(
            logsDirectory: temporaryDirectory,
            logsFileCreationDateProvider: fileCreationDatesProvider,
            logsUploadInterval: logsUploadInterval,
            logsTimeProvider: logDatesProvider,
            requestsRecorder: requestsRecorder
        )

        // Fulfill expectation on every request sent
        requestsRecorder.onNewRequest = { _ in expectation.fulfill() }

        // Execute test
        test()

        // Wait for all requests being sent
        let arbitraryEnoughOfTime = logsUploadInterval * Double(expectedRequestsCount) * 3
        waitForExpectations(timeout: arbitraryEnoughOfTime, handler: nil)

        try Datadog.deinitializeOrThrow()

        return requestsRecorder
    }

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
