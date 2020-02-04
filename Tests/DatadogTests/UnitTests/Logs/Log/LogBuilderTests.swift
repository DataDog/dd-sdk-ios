import XCTest
@testable import Datadog

class LogBuilderTests: XCTestCase {
    let builder = LogBuilder(
        serviceName: "test-service-name",
        loggerName: "test-logger-name",
        dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    )

    func testItBuildsBasicLog() {
        let log = builder.createLogWith(
            level: .debug,
            message: "debug message",
            attributes: ["attribute": "value"],
            tags: ["tag"]
        )

        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.status, .debug)
        XCTAssertEqual(log.message, "debug message")
        XCTAssertEqual(log.serviceName, "test-service-name")
        XCTAssertEqual(log.loggerName, "test-logger-name")
        XCTAssertEqual(log.tags, ["tag"])
        XCTAssertEqual(log.attributes, ["attribute": EncodableValue("value")])
        XCTAssertEqual(
            builder.createLogWith(level: .info, message: "", attributes: [:], tags: []).status, .info
        )
        XCTAssertEqual(
            builder.createLogWith(level: .notice, message: "", attributes: [:], tags: []).status, .notice
        )
        XCTAssertEqual(
            builder.createLogWith(level: .warn, message: "", attributes: [:], tags: []).status, .warn
        )
        XCTAssertEqual(
            builder.createLogWith(level: .error, message: "", attributes: [:], tags: []).status, .error
        )
        XCTAssertEqual(
            builder.createLogWith(level: .critical, message: "", attributes: [:], tags: []).status, .critical
        )
    }
}
