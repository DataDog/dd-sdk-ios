/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class NewFeatureBaggageTests: XCTestCase {
    struct GroceryProduct: Encodable {
        var name: String
        var points: Int
        var description: String?
    }

    struct CartItem: Decodable {
        var name: String
        var points: Int
    }

    func testEncodeDecode() throws {
        let pear = GroceryProduct(name: .mockRandom(), points: .mockRandom(), description: .mockRandom())
        let baggage = try NewFeatureBaggage(pear)
        let item: CartItem = try baggage.decode()

        XCTAssertEqual(pear.name, item.name)
        XCTAssertEqual(pear.points, item.points)
    }
}
