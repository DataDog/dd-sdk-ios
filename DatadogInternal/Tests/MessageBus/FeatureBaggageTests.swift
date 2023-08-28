/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class FeatureBaggageTests: XCTestCase {
    struct GroceryProduct: Encodable, RandomMockable {
        var name: String
        var points: Int
        var description: String?

        static func mockRandom() -> Self {
            .init(
                name: .mockRandom(),
                points: .mockRandom(),
                description: .mockRandom()
            )
        }
    }

    struct CartItem: Decodable {
        var name: String
        var points: Int
    }

    func testEncodeDecode() throws {
        let pear = GroceryProduct.mockRandom()
        let baggage = FeatureBaggage(pear)
        let item: CartItem = try baggage.decode()

        XCTAssertEqual(pear.name, item.name)
        XCTAssertEqual(pear.points, item.points)
    }

    func testEncodingFailure() throws {
        struct FaultyEncodable: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    self,
                    .init(codingPath: [], debugDescription: "FaultyEncodable")
                )
            }
        }

        let faulty = FaultyEncodable()
        let baggage = FeatureBaggage(faulty)
        XCTAssertThrowsError(try baggage.decode(type: CartItem.self)) {
            XCTAssert($0 is EncodingError)
        }
    }

    func testDecodingFailure() throws {
        struct FaultyDecodable: Decodable {
            init(from decoder: Decoder) throws {
                throw DecodingError.valueNotFound(
                    FaultyDecodable.self,
                    .init(codingPath: [], debugDescription: "FaultyDecodable")
                )
            }
        }

        let pear = GroceryProduct.mockRandom()
        let baggage = FeatureBaggage(pear)
        XCTAssertThrowsError(try baggage.decode(type: FaultyDecodable.self)) { error in
            XCTAssert(error is DecodingError)
        }
    }

    func testThreadSafety() {
        let pear = GroceryProduct.mockRandom()
        let baggage = FeatureBaggage(pear)
        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = try? baggage.encode() },
                { _ = try? baggage.decode(type: CartItem.self) }
            ],
            iterations: 100
        )
        // swiftlint:enable opening_brace
    }
}
