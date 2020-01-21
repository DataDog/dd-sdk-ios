import XCTest
@testable import Datadog

// swiftlint:disable multiline_arguments_brackets
class LoggerTests: XCTestCase {
    /// Provides consecutive dates for send with `Logger`.
    private var logDatesProvider: DateProvider {
        let provider = DateProviderMock()
        provider.currentDates = [
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -5),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -4),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -3),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -2),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -1),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 0),
        ]
        return provider
    }

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
          "date" : "2019-12-15T09:59:55Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[1], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T09:59:56Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[2], fullyMatches: """
        [{
          "status" : "NOTICE",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T09:59:57Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[3], fullyMatches: """
        [{
          "status" : "WARN",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T09:59:58Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[4], fullyMatches: """
        [{
          "status" : "ERROR",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T09:59:59Z"
        }]
        """)
        assertThat(jsonArrayData: requestsData[5], fullyMatches: """
        [{
          "status" : "CRITICAL",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T10:00:00Z"
        }]
        """)
    }

    func testSendingLogsWithCustomizedLogger() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 6) {
            let logger = Logger.builder
                .set(serviceName: "custom-service-name")
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
        }
    }

    // MARK: - Adding attributes

    func testSendingAttributesOfDifferentEncodableValues() throws {
        let requestsRecorder = try setUpDatadogAndRecordSendingOneLogPerRequest(expectedRequestsCount: 1) {
            let logger = Logger.builder.build()

            // boolean literal
            logger.addAttribute(key: "Bool", value: true)

            // integer literal
            logger.addAttribute(key: "Int", value: 10)

            // Typed 8-bit unsigned Integer
            logger.addAttribute(key: "UInt8", value: UInt8(10))

            // double-precision, floating-point value
            logger.addAttribute(key: "Double", value: 10.5)

            // array of `Encodable` integer
            logger.addAttribute(key: "Array<Int>", value: [1, 2, 3])

            // dictionary of `Encodable` date types
            logger.addAttribute(key: "Dictionary<String: Date>", value: [
                "date1": Date.mockDecember15th2019At10AMUTC(),
                "date2": Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 60 * 60)
            ])

            struct Person: Codable {
                let name: String
                let age: Int
                let nationality: String
            }

            // custom `Encodable` structure
            logger.addAttribute(key: "Person", value: Person(name: "Adam", age: 30, nationality: "Polish"))

            logger.info("message")
        }

        let requestsData = requestsRecorder.requestsSent.compactMap { $0.httpBody }
        assertThat(jsonArrayData: requestsData[0], fullyMatches: """
        [{
          "status" : "INFO",
          "message" : "message",
          "service" : "ios",
          "date" : "2019-12-15T09:59:55Z",
          "Bool" : true,
          "Int" : 10,
          "UInt8" : 10,
          "Double" : 10.5,
          "Array<Int>" : [1, 2, 3],
          "Dictionary<String: Date>" : {
             "date1": "2019-12-15T10:00:00Z",
             "date2": "2019-12-15T11:00:00Z"
          },
          "Person" : {
             "name" : "Adam",
             "age" : 30,
             "nationality" : "Polish",
          }
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

        // Set up `DateProvider` for creating log files in the past
        let fileCreationDateProvider = DateProviderMock()
        fileCreationDateProvider.currentFileCreationDates = (0..<expectedRequestsCount)
            .map { Date().secondsAgo(Double($0) * 10) } // create file every 10 seconds in the past ...
            .reversed() // ... starting from oldest time

        let logsUploadInterval: TimeInterval = 0.05 // pretty quick 😎

        // Configure `Datadog` instance
        Datadog.instance = .mockSuccessfullySendingOneLogPerRequest(
            logsDirectory: temporaryDirectory,
            logsFileCreationDateProvider: fileCreationDateProvider,
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
