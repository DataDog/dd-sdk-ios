import XCTest
@testable import Datadog

class LoggerTests: XCTestCase {
    func testItSendsLogsWithDifferentStatus() {
        let expectation = self.expectation(description: "send 6 logs of different status")
        expectation.expectedFulfillmentCount = 6

        // List of `Logger` methods to test
        let loggingMethods = [
            Logger.debug,
            Logger.info,
            Logger.notice,
            Logger.warn,
            Logger.error,
            Logger.critical,
        ]

        // Corresponding collection of matches applied on `.httpData` field of `URLRequest` objects sent by `Logger`
        let expectedRequestBodyMatches = [
            (value: ["DEBUG"],    keyPath: "@unionOfObjects.status"),
            (value: ["INFO"],     keyPath: "@unionOfObjects.status"),
            (value: ["NOTICE"],   keyPath: "@unionOfObjects.status"),
            (value: ["WARN"],     keyPath: "@unionOfObjects.status"),
            (value: ["ERROR"],    keyPath: "@unionOfObjects.status"),
            (value: ["CRITICAL"], keyPath: "@unionOfObjects.status"),
        ]

        // TODO: RUMM-109 Rewrite by determining if logs are properly written to file
        // TODO: RUMM-109 Move integration tests (asserting uploads) to `DatadogTests`.
        _ = loggingMethods
        _ = expectedRequestBodyMatches
    }
}

class LoggerBuilderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    func testItBuildsDefaultLogger() throws {
        Datadog.initialize(
            endpointURL: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        let logger = Logger.builder.build()

        // TODO: RUMM-109 Rewrite

        try Datadog.deinitializeOrThrow()
    }

    func testItBuildsParametrizedLogger() throws {
        Datadog.initialize(
            endpointURL: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        let logger = Logger.builder
            .set(serviceName: "abcd")
            .build()

        // TODO: RUMM-109 Rewrite

        try Datadog.deinitializeOrThrow()
    }

    func testWhenDatadogIsNotInitialized_itThrowsProgrammerError() {
        XCTAssertThrowsError(try Logger.builder.buildOrThrow()) { error in
            XCTAssertEqual(
                (error as? ProgrammerError)?.description,
                "Datadog SDK usage error: `Datadog.initialize()` must be called prior to `Logger.builder.build()`."
            )
        }
    }
}
