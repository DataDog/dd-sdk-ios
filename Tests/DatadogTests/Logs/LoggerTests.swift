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

        zip(loggingMethods, expectedRequestBodyMatches).forEach { method, expectedRequestBodyMatch in
            let loggerInstance = Logger(
                uploader: .mockUploaderCapturingRequests(captureBlock: { [unowned self] request in
                    self.assertThat(
                        serializedLogData: request.httpBody ?? Data(),
                        matchesValue: expectedRequestBodyMatch.value,
                        onKeyPath: expectedRequestBodyMatch.keyPath
                    )
                    expectation.fulfill()
                })
            )
            let loggingMethodInvocation = method(loggerInstance)
            loggingMethodInvocation("some message")
        }

        waitForExpectations(timeout: 1, handler: nil)
    }
}
