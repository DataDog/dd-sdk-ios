import XCTest
@testable import Datadog

class LoggingTests: XCTestCase {
    private let serverMock = ServerMock()

    override func setUp() {
        super.setUp()
        serverMock.start()
        Datadog.initialize(endpointURL: serverMock.url, clientToken: "abcd")
    }

    override func tearDown() {
        try! Datadog.deinitializeOrThrow()
        serverMock.stop()
        super.tearDown()
    }

    func testItDoesSomething() throws {
        let logger = Logger.builder
            .printLogsToConsole(true)
            .build()

        logger.info("HELLO!")
        logger.info("How")
        logger.info("are")
        logger.info("you?")

        Thread.sleep(forTimeInterval: 30)

        try serverMock.verify { session in
            let logRequests = try session.recordedRequests.map { try $0.asLogsRequest() }
            XCTAssertEqual(logRequests.reduce(0) { acc, next in acc + next.logJSONs.count }, 4)
        }
    }
}
