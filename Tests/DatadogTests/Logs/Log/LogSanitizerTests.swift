import XCTest
@testable import Datadog

class LogSanitizerTests: XCTestCase {
    func testWhenAttributeUsesReservedName_itIsIgnored() {
        let log = Log(
            date: .mockAny(),
            status: .mockAny(),
            message: .mockAny(),
            service: .mockAny(),
            attributes: [
                // reserved attributes:
                "host": .mockAny(),
                "message": .mockAny(),
                "status": .mockAny(),
                "service": .mockAny(),
                "source": .mockAny(),
                "error.kind": .mockAny(),
                "error.message": .mockAny(),
                "error.stack": .mockAny(),
                "ddtags": .mockAny(),

                // valid attributes:
                "attribute1": .mockAny(),
                "attribute2": .mockAny(),
                "date": .mockAny(), // 💡 date is not a reserved attribute
            ],
            tags: []
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 3)
        XCTAssertNotNil(sanitized.attributes?["attribute1"])
        XCTAssertNotNil(sanitized.attributes?["attribute2"])
        XCTAssertNotNil(sanitized.attributes?["date"])
    }

    func testWhenAttributeNameExceeds10NestedLevels_itIsEscapedByUnderscore() {
        let log = Log(
            date: .mockAny(),
            status: .mockAny(),
            message: .mockAny(),
            service: .mockAny(),
            attributes: [
                "one": .mockAny(),
                "one.two": .mockAny(),
                "one.two.three": .mockAny(),
                "one.two.three.four": .mockAny(),
                "one.two.three.four.five": .mockAny(),
                "one.two.three.four.five.six": .mockAny(),
                "one.two.three.four.five.six.seven": .mockAny(),
                "one.two.three.four.five.six.seven.eight": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven": .mockAny(),
                "one.two.three.four.five.six.seven.eight.nine.ten.eleven.twelve": .mockAny(),
            ],
            tags: []
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 12)
        XCTAssertNotNil(sanitized.attributes?["one"])
        XCTAssertNotNil(sanitized.attributes?["one.two"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven"])
        XCTAssertNotNil(sanitized.attributes?["one.two.three.four.five.six.seven.eight.nine.ten_eleven_twelve"])
    }

    func testWhenNumberOfAttributesExceedsLimit_itDropsExtraOnes() {
        let mockAttributes = (0...1_000).map { index in ("attribute-\(index)", EncodableValue.mockAny()) }
        let log = Log(
            date: .mockAny(),
            status: .mockAny(),
            message: .mockAny(),
            service: .mockAny(),
            attributes: Dictionary(uniqueKeysWithValues: mockAttributes),
            tags: []
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, LogSanitizer.Constraints.maxNumberOfAttributes)
    }

    func testWhenAttributeNameIsInvalid_itIsIgnored() {
        let log = Log(
            date: .mockAny(),
            status: .mockAny(),
            message: .mockAny(),
            service: .mockAny(),
            attributes: [
                "valid-name": .mockAny(),
                "": .mockAny(), // invalid name
            ],
            tags: []
        )

        let sanitized = LogSanitizer().sanitize(log: log)

        XCTAssertEqual(sanitized.attributes?.count, 1)
        XCTAssertNotNil(sanitized.attributes?["valid-name"])
    }
}
