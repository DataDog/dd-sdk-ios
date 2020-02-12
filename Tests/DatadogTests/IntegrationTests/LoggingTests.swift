import XCTest
@testable import Datadog

#if os(macOS) // TODO: RUMM-216 Integration tests can be run on simulator and device
class LoggingTests: XCTestCase {
    private let serverMock = ServerMock()

    override func setUp() {
        super.setUp()
        serverMock.start()
        Datadog.initialize(
            appContext: AppContext(
                bundleIdentifier: "com.datadoghq.ios-sdk",
                bundleVersion: "1.0.0",
                bundleShortVersion: "1.0.0",
                executableName: "some-app",
                mobileDevice: nil
            ),
            endpointURL: serverMock.url,
            clientToken: "abcd"
        )
    }

    override func tearDown() {
        try! Datadog.deinitializeOrThrow()
        serverMock.stop()
        super.tearDown()
    }

    // swiftlint:disable trailing_closure
    func testLogsWithTagsAndAttributesAreUploadedToServer() throws {
        // Configure logger
        let logger = Logger.builder
            .printLogsToConsole(true)
            .set(serviceName: "service-name")
            .set(loggerName: "logger-name")
            .build()

        // Send logs
        logger.addTag(withKey: "tag1", value: "tag-value")
        logger.add(tag: "tag2")

        logger.addAttribute(forKey: "logger-attribute1", value: "string value")
        logger.addAttribute(forKey: "logger-attribute2", value: 1_000)

        logger.debug("debug message", attributes: ["attribute": "value"])
        logger.info("info message", attributes: ["attribute": "value"])
        logger.notice("notice message", attributes: ["attribute": "value"])
        logger.warn("warn message", attributes: ["attribute": "value"])
        logger.error("error message", attributes: ["attribute": "value"])
        logger.critical("critical message", attributes: ["attribute": "value"])

        // Wait for delivery
        Thread.sleep(forTimeInterval: 30)

        // Assert
        try serverMock.verify { (session: ServerSession) in
            let logMatchers = try session.recordedRequests
                .flatMap { request in try request.body.toArrayOfJSONObjects() }
                .map { jsonObject in LogMatcher(from: jsonObject) }

            logMatchers[0].assertStatus(equals: "DEBUG")
            logMatchers[0].assertMessage(equals: "debug message")

            logMatchers[1].assertStatus(equals: "INFO")
            logMatchers[1].assertMessage(equals: "info message")

            logMatchers[2].assertStatus(equals: "NOTICE")
            logMatchers[2].assertMessage(equals: "notice message")

            logMatchers[3].assertStatus(equals: "WARN")
            logMatchers[3].assertMessage(equals: "warn message")

            logMatchers[4].assertStatus(equals: "ERROR")
            logMatchers[4].assertMessage(equals: "error message")

            logMatchers[5].assertStatus(equals: "CRITICAL")
            logMatchers[5].assertMessage(equals: "critical message")

            logMatchers.forEach { matcher in
                matcher.assertDate(matches: { $0.isNotOlderThan(seconds: 60) })
                matcher.assertServiceName(equals: "service-name")
                matcher.assertLoggerName(equals: "logger-name")
                matcher.assertLoggerVersion(equals: sdkVersion)
                matcher.assertApplicationVersion(equals: "1.0.0")
                matcher.assertThreadName(equals: "main")
                matcher.assertAttributes(
                    equal: [
                        "logger-attribute1": "string value",
                        "logger-attribute2": 1_000,
                        "attribute": "value",
                    ]
                )
                matcher.assertTags(equal: ["tag1:tag-value", "tag2"])
            }
        }
    }
    // swiftlint:enable trailing_closure
}
#endif
