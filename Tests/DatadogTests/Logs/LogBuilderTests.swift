import XCTest
@testable import Datadog

class LogBuilderTests: XCTestCase {
    let builder = LogBuilder(
        serviceName: "test-service-name",
        dateProvider: DateProviderMock(currentDate: .mockDecember15th2019At10AMUTC())
    )

    func testItBuildsBasicLog() {
        let log = builder.createLogWith(level: .debug, message: "debug message", attributes: [:])

        XCTAssertEqual(log.date, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(log.status, .debug)
        XCTAssertEqual(log.message, "debug message")
        XCTAssertEqual(log.service, "test-service-name")
        XCTAssertEqual(builder.createLogWith(level: .info, message: "", attributes: [:]).status, .info)
        XCTAssertEqual(builder.createLogWith(level: .notice, message: "", attributes: [:]).status, .notice)
        XCTAssertEqual(builder.createLogWith(level: .warn, message: "", attributes: [:]).status, .warn)
        XCTAssertEqual(builder.createLogWith(level: .error, message: "", attributes: [:]).status, .error)
        XCTAssertEqual(builder.createLogWith(level: .critical, message: "", attributes: [:]).status, .critical)
    }

    func testWhenAttributeWithReservedNameIsSpecified_itIsIgnored() {
        let log = builder.createLogWith(
            level: .debug,
            message: "debug message",
            attributes: [
                // reserved attributes:
                "host": String.mockAny(),
                "message": String.mockAny(),
                "status": String.mockAny(),
                "service": String.mockAny(),
                "source": String.mockAny(),
                "date": String.mockAny(),
                "error.kind": String.mockAny(),
                "error.message": String.mockAny(),
                "error.stack": String.mockAny(),
                "ddtags": String.mockAny(),

                // valid attributes:
                "attribute1": String.mockAny(),
                "attribute2": String.mockAny(),
            ]
        )

        XCTAssertEqual(log.attributes?.count, 2)
        XCTAssertNotNil(log.attributes?["attribute1"])
        XCTAssertNotNil(log.attributes?["attribute2"])
    }

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let log = builder.createLogWith(
            level: .debug,
            message: "",
            attributes: [
                "one": String.mockAny(),
                "one.two": String.mockAny(),
                "one.two.three": String.mockAny(),
                "one.two.three.four": String.mockAny(),
                "one.two.three.four.five": String.mockAny(),
                "one.two.three.four.five.six": String.mockAny(),
                "one.two.three.four.five.six.seven": String.mockAny(),
                "one.two.three.four.five.six.seven.eight": String.mockAny(),
                "one.two.three.four.five.six.seven.eight.nine": String.mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten": String.mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven": String.mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": String.mockAny(),
            ]
        )

        XCTAssertEqual(log.attributes?.count, 12)
        XCTAssertNotNil(log.attributes?["one"])
        XCTAssertNotNil(log.attributes?["one.two"])
        XCTAssertNotNil(log.attributes?["one.two.three"])
        XCTAssertNotNil(log.attributes?["one.two.three.four"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six.seven"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(log.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let mockAttributes = (0...1_000).map { index in ("attribute-\(index)", String.mockAny()) }
        let log = builder.createLogWith(
            level: .debug,
            message: "",
            attributes: Dictionary(uniqueKeysWithValues: mockAttributes)
        )

        XCTAssertEqual(log.attributes?.count, LogBuilder.Constants.maxNumberOfAttributes)
    }
}
