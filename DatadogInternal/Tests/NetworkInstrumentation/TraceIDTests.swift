/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class TraceIDTests: XCTestCase {
    func testToHexadecimalStringConversion() {
        // 64 bit or less
        XCTAssertEqual(String(TraceID(rawValue: (0, 0)), representation: .hexadecimal), "0")
        XCTAssertEqual(String(TraceID(rawValue: (0, 1)), representation: .hexadecimal), "1")
        XCTAssertEqual(String(TraceID(rawValue: (0, 15)), representation: .hexadecimal), "f")
        XCTAssertEqual(String(TraceID(rawValue: (0, 16)), representation: .hexadecimal), "10")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123)), representation: .hexadecimal), "7b")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123_456)), representation: .hexadecimal), "1e240")
        XCTAssertEqual(String(TraceID(rawValue: (0, .max)), representation: .hexadecimal), "ffffffffffffffff")

        // 128 bit
        XCTAssertEqual(String(TraceID(rawValue: (1, 0)), representation: .hexadecimal), "10000000000000000")
        XCTAssertEqual(String(TraceID(rawValue: (1, 1)), representation: .hexadecimal), "10000000000000001")
        XCTAssertEqual(String(TraceID(rawValue: (15, 15)), representation: .hexadecimal), "f000000000000000f")
        XCTAssertEqual(String(TraceID(rawValue: (16, 16)), representation: .hexadecimal), "100000000000000010")
        XCTAssertEqual(String(TraceID(rawValue: (123, 123)), representation: .hexadecimal), "7b000000000000007b")
        XCTAssertEqual(String(TraceID(rawValue: (123_456, 123_456)), representation: .hexadecimal), "1e240000000000001e240")
        XCTAssertEqual(String(TraceID(rawValue: (.max, .max)), representation: .hexadecimal), "ffffffffffffffffffffffffffffffff")
    }

    func testTo16CharHexadecimalStringConversion() {
        XCTAssertEqual(String(TraceID(rawValue: (0, 0)), representation: .hexadecimal16Chars), "0000000000000000")
        XCTAssertEqual(String(TraceID(rawValue: (0, 1)), representation: .hexadecimal16Chars), "0000000000000001")
        XCTAssertEqual(String(TraceID(rawValue: (0, 15)), representation: .hexadecimal16Chars), "000000000000000f")
        XCTAssertEqual(String(TraceID(rawValue: (0, 16)), representation: .hexadecimal16Chars), "0000000000000010")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123)), representation: .hexadecimal16Chars), "000000000000007b")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123_456)), representation: .hexadecimal16Chars), "000000000001e240")
        XCTAssertEqual(String(TraceID(rawValue: (0, .max)), representation: .hexadecimal16Chars), "ffffffffffffffff")
    }

    func testTo32CharHexadecimalStringConversion() {
        // 64 bit
        XCTAssertEqual(String(TraceID(rawValue: (0, 0)), representation: .hexadecimal32Chars), "00000000000000000000000000000000")
        XCTAssertEqual(String(TraceID(rawValue: (0, 1)), representation: .hexadecimal32Chars), "00000000000000000000000000000001")
        XCTAssertEqual(String(TraceID(rawValue: (0, 15)), representation: .hexadecimal32Chars), "0000000000000000000000000000000f")
        XCTAssertEqual(String(TraceID(rawValue: (0, 16)), representation: .hexadecimal32Chars), "00000000000000000000000000000010")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123)), representation: .hexadecimal32Chars), "0000000000000000000000000000007b")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123_456)), representation: .hexadecimal32Chars), "0000000000000000000000000001e240")
        XCTAssertEqual(String(TraceID(rawValue: (0, .max)), representation: .hexadecimal32Chars), "0000000000000000ffffffffffffffff")

        // 128 bit
        XCTAssertEqual(String(TraceID(rawValue: (1, 0)), representation: .hexadecimal32Chars), "00000000000000010000000000000000")
        XCTAssertEqual(String(TraceID(rawValue: (1, 1)), representation: .hexadecimal32Chars), "00000000000000010000000000000001")
        XCTAssertEqual(String(TraceID(rawValue: (15, 15)), representation: .hexadecimal32Chars), "000000000000000f000000000000000f")
        XCTAssertEqual(String(TraceID(rawValue: (16, 16)), representation: .hexadecimal32Chars), "00000000000000100000000000000010")
        XCTAssertEqual(String(TraceID(rawValue: (123, 123)), representation: .hexadecimal32Chars), "000000000000007b000000000000007b")
        XCTAssertEqual(String(TraceID(rawValue: (123_456, 123_456)), representation: .hexadecimal32Chars), "000000000001e240000000000001e240")
        XCTAssertEqual(String(TraceID(rawValue: (.max, .max)), representation: .hexadecimal32Chars), "ffffffffffffffffffffffffffffffff")
    }
    func testToDecimalStringConversion() {
        XCTAssertEqual(String(TraceID(rawValue: (0, 0)), representation: .decimal), "0")
        XCTAssertEqual(String(TraceID(rawValue: (0, 1)), representation: .decimal), "1")
        XCTAssertEqual(String(TraceID(rawValue: (0, 15)), representation: .decimal), "15")
        XCTAssertEqual(String(TraceID(rawValue: (0, 16)), representation: .decimal), "16")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123)), representation: .decimal), "123")
        XCTAssertEqual(String(TraceID(rawValue: (0, 123_456)), representation: .decimal), "123456")
        XCTAssertEqual(String(TraceID(rawValue: (0, .max)), representation: .decimal), "\(UInt64.max)")
    }

    func testInitializationFromHexadecimal() {
        // 64 bit or less
        XCTAssertEqual(TraceID("0", representation: .hexadecimal), 0)
        XCTAssertEqual(TraceID("1", representation: .hexadecimal), 1)
        XCTAssertEqual(TraceID("f", representation: .hexadecimal), 15)
        XCTAssertEqual(TraceID("10", representation: .hexadecimal), 16)
        XCTAssertEqual(TraceID("7b", representation: .hexadecimal), 123)
        XCTAssertEqual(TraceID("1e240", representation: .hexadecimal), 123_456)
        XCTAssertEqual(TraceID("FFFFFFFFFFFFFFFF", representation: .hexadecimal), TraceID(rawValue: (0, .max)))

        // 128 bit
        XCTAssertEqual(TraceID("10000000000000000", representation: .hexadecimal), TraceID(rawValue: (1, 0)))
        XCTAssertEqual(TraceID("10000000000000001", representation: .hexadecimal), TraceID(rawValue: (1, 1)))
        XCTAssertEqual(TraceID("f000000000000000f", representation: .hexadecimal), TraceID(rawValue: (15, 15)))
        XCTAssertEqual(TraceID("100000000000000010", representation: .hexadecimal), TraceID(rawValue: (16, 16)))
        XCTAssertEqual(TraceID("7b000000000000007b", representation: .hexadecimal), TraceID(rawValue: (123, 123)))
        XCTAssertEqual(TraceID("1e240000000000001e240", representation: .hexadecimal), TraceID(rawValue: (123_456, 123_456)))
        XCTAssertEqual(TraceID("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", representation: .hexadecimal), TraceID(rawValue: (.max, .max)))
    }

    func testInitializationFromDecimal() {
        XCTAssertEqual(String(TraceID("0")!, representation: .hexadecimal), "0")
        XCTAssertEqual(String(TraceID("1")!, representation: .hexadecimal), "1")
        XCTAssertEqual(String(TraceID("15")!, representation: .hexadecimal), "f")
        XCTAssertEqual(String(TraceID("16")!, representation: .hexadecimal), "10")
        XCTAssertEqual(String(TraceID("123")!, representation: .hexadecimal), "7b")
        XCTAssertEqual(String(TraceID("123456")!, representation: .hexadecimal), "1e240")
        XCTAssertEqual(String(TraceID("\(UInt64.max)")!, representation: .hexadecimal), "ffffffffffffffff")
    }

    func testDecodableFromHexadecimal() {
        let json = "\"1e240\""
        let decoder = JSONDecoder()
        let traceID = try! decoder.decode(TraceID.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(traceID, TraceID(rawValue: (0, 123_456)))
    }

    func testDecodableUnknownFormat() {
        let json = "1234"
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(TraceID.self, from: json.data(using: .utf8)!) as TraceID)
    }

    func testEncodableToHexadecimal() {
        let traceID = TraceID(rawValue: (0, 123_456))
        let encoder = JSONEncoder()
        let json = try! encoder.encode(traceID)
        XCTAssertEqual(String(data: json, encoding: .utf8), "\"1e240\"")
    }

    func testIdHiHex() {
        XCTAssertEqual(TraceID(rawValue: (0, 0)).idHiHex, "0")
        XCTAssertEqual(TraceID(rawValue: (1, 0)).idHiHex, "1")
        XCTAssertEqual(TraceID(rawValue: (15, 0)).idHiHex, "f")
        XCTAssertEqual(TraceID(rawValue: (16, 0)).idHiHex, "10")
        XCTAssertEqual(TraceID(rawValue: (123, 0)).idHiHex, "7b")
        XCTAssertEqual(TraceID(rawValue: (123_456, 0)).idHiHex, "1e240")
        XCTAssertEqual(TraceID(rawValue: (.max, 0)).idHiHex, "ffffffffffffffff")
    }

    func testIdLoHex() {
        XCTAssertEqual(TraceID(rawValue: (0, 0)).idLoHex, "0")
        XCTAssertEqual(TraceID(rawValue: (0, 1)).idLoHex, "1")
        XCTAssertEqual(TraceID(rawValue: (0, 15)).idLoHex, "f")
        XCTAssertEqual(TraceID(rawValue: (0, 16)).idLoHex, "10")
        XCTAssertEqual(TraceID(rawValue: (0, 123)).idLoHex, "7b")
        XCTAssertEqual(TraceID(rawValue: (0, 123_456)).idLoHex, "1e240")
        XCTAssertEqual(TraceID(rawValue: (0, .max)).idLoHex, "ffffffffffffffff")
    }

    func testToString() {
        // hexadecimal
        XCTAssertEqual(TraceID(rawValue: (0, 0)).toString(representation: .hexadecimal), "0")
        XCTAssertEqual(TraceID(rawValue: (0, 1)).toString(representation: .hexadecimal), "1")
        XCTAssertEqual(TraceID(rawValue: (0, 15)).toString(representation: .hexadecimal), "f")
        XCTAssertEqual(TraceID(rawValue: (0, 16)).toString(representation: .hexadecimal), "10")
        XCTAssertEqual(TraceID(rawValue: (0, 123)).toString(representation: .hexadecimal), "7b")
        XCTAssertEqual(TraceID(rawValue: (0, 123_456)).toString(representation: .hexadecimal), "1e240")
        XCTAssertEqual(TraceID(rawValue: (0, .max)).toString(representation: .hexadecimal), "ffffffffffffffff")
        XCTAssertEqual(TraceID(rawValue: (1, .max)).toString(representation: .hexadecimal), "1ffffffffffffffff")
        XCTAssertEqual(TraceID(rawValue: (.max, .max)).toString(representation: .hexadecimal), "ffffffffffffffffffffffffffffffff")

        // hexadecimal16Chars
        XCTAssertEqual(TraceID(rawValue: (0, 0)).toString(representation: .hexadecimal16Chars), "0000000000000000")
        XCTAssertEqual(TraceID(rawValue: (0, 1)).toString(representation: .hexadecimal16Chars), "0000000000000001")
        XCTAssertEqual(TraceID(rawValue: (0, 15)).toString(representation: .hexadecimal16Chars), "000000000000000f")
        XCTAssertEqual(TraceID(rawValue: (0, 16)).toString(representation: .hexadecimal16Chars), "0000000000000010")
        XCTAssertEqual(TraceID(rawValue: (0, 123)).toString(representation: .hexadecimal16Chars), "000000000000007b")
        XCTAssertEqual(TraceID(rawValue: (0, 123_456)).toString(representation: .hexadecimal16Chars), "000000000001e240")
        XCTAssertEqual(TraceID(rawValue: (0, .max)).toString(representation: .hexadecimal16Chars), "ffffffffffffffff")
        XCTAssertEqual(TraceID(rawValue: (1, .max)).toString(representation: .hexadecimal16Chars), "ffffffffffffffff")
        XCTAssertEqual(TraceID(rawValue: (.max, .max)).toString(representation: .hexadecimal16Chars), "ffffffffffffffff")

        // hexadecimal32Chars
        XCTAssertEqual(TraceID(rawValue: (0, 0)).toString(representation: .hexadecimal32Chars), "00000000000000000000000000000000")
        XCTAssertEqual(TraceID(rawValue: (0, 1)).toString(representation: .hexadecimal32Chars), "00000000000000000000000000000001")
        XCTAssertEqual(TraceID(rawValue: (0, 15)).toString(representation: .hexadecimal32Chars), "0000000000000000000000000000000f")
        XCTAssertEqual(TraceID(rawValue: (0, 16)).toString(representation: .hexadecimal32Chars), "00000000000000000000000000000010")
        XCTAssertEqual(TraceID(rawValue: (0, 123)).toString(representation: .hexadecimal32Chars), "0000000000000000000000000000007b")
        XCTAssertEqual(TraceID(rawValue: (0, 123_456)).toString(representation: .hexadecimal32Chars), "0000000000000000000000000001e240")
        XCTAssertEqual(TraceID(rawValue: (0, .max)).toString(representation: .hexadecimal32Chars), "0000000000000000ffffffffffffffff")
        XCTAssertEqual(TraceID(rawValue: (1, .max)).toString(representation: .hexadecimal32Chars), "0000000000000001ffffffffffffffff")

        // decimal
        XCTAssertEqual(TraceID(rawValue: (0, 0)).toString(representation: .decimal), "0")
        XCTAssertEqual(TraceID(rawValue: (0, 1)).toString(representation: .decimal), "1")
        XCTAssertEqual(TraceID(rawValue: (0, 15)).toString(representation: .decimal), "15")
        XCTAssertEqual(TraceID(rawValue: (0, 16)).toString(representation: .decimal), "16")
        XCTAssertEqual(TraceID(rawValue: (0, 123)).toString(representation: .decimal), "123")
        XCTAssertEqual(TraceID(rawValue: (0, 123_456)).toString(representation: .decimal), "123456")
        XCTAssertEqual(TraceID(rawValue: (0, .max)).toString(representation: .decimal), "\(UInt64.max)")
        XCTAssertEqual(TraceID(rawValue: (1, .max)).toString(representation: .decimal), "\(UInt64.max)")
        XCTAssertEqual(TraceID(rawValue: (.max, .max)).toString(representation: .decimal), "\(UInt64.max)")
    }

    func testDefaultInit() {
        XCTAssertEqual(TraceID().rawValue.0, 0)
        XCTAssertEqual(TraceID().rawValue.1, 0)
    }
}
