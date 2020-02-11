import XCTest
@testable import Datadog

class LogBuilderTests: XCTestCase {
    let builder = LogBuilder(
        appContext: .mockWith(
            bundleIdentifier: "com.datadoghq.ios-sdk",
            bundleVersion: "1.0.0",
            bundleShortVersion: "1.0.0"
        ),
        serviceName: "test-service-name",
        loggerName: "test-logger-name",
        dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
        userInfoProvider: .mockWith(
            userInfo: UserInfo(id: "abc-123", name: "Foo", email: "foo@example.com")
        )
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

    func testItSetsThreadNameAttribute() {
        let expectation = self.expectation(description: "create all logs")
        expectation.expectedFulfillmentCount = 3

        DispatchQueue.main.async {
            let log = self.builder.createLogWith(level: .debug, message: "", attributes: [:], tags: [])
            XCTAssertEqual(log.threadName, "main")
            expectation.fulfill()
        }

        DispatchQueue.global(qos: .default).async {
            let log = self.builder.createLogWith(level: .debug, message: "", attributes: [:], tags: [])
            XCTAssertEqual(log.threadName, "background")
            expectation.fulfill()
        }

        DispatchQueue(label: "custom-queue").async {
            let previousName = Thread.current.name
            defer { Thread.current.name = previousName } // reset it as this thread might be picked by `.global(qos: .default)`

            Thread.current.name = "custom-thread-name"
            let log = self.builder.createLogWith(level: .debug, message: "", attributes: [:], tags: [])
            XCTAssertEqual(log.threadName, "custom-thread-name")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)
    }

    func testItSetsApplicationVersionAttribute() {
        func createLogUsing(appContext: AppContext) -> Log {
            let builder = LogBuilder(
                appContext: appContext,
                serviceName: .mockAny(),
                loggerName: .mockAny(),
                dateProvider: SystemDateProvider(),
                userInfoProvider: .mockAny()
            )

            return builder.createLogWith(level: .debug, message: "", attributes: [:], tags: [])
        }

        // When only `bundle.version` is available
        var log = createLogUsing(appContext: .mockWith(bundleVersion: "version", bundleShortVersion: nil))
        XCTAssertEqual(log.applicationVersion, "version")

        // When only `bundle.shortVersion` is available
        log = createLogUsing(appContext: .mockWith(bundleVersion: nil, bundleShortVersion: "shortVersion"))
        XCTAssertEqual(log.applicationVersion, "shortVersion")

        // When both `bundle.version` and `bundle.shortVersion` are available
        log = createLogUsing(appContext: .mockWith(bundleVersion: "version", bundleShortVersion: "shortVersion"))
        XCTAssertEqual(log.applicationVersion, "shortVersion")

        // When neither of `bundle.version` and `bundle.shortVersion` is available
        log = createLogUsing(appContext: .mockWith(bundleVersion: nil, bundleShortVersion: nil))
        XCTAssertEqual(log.applicationVersion, "")
    }
}
