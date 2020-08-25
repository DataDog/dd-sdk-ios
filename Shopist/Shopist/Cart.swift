/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal let cart = Cart()

extension Float {
    var moneyString: String { String(format: "€%.2f", self) }
}

internal final class Cart {
    static let taxPercentage: Float = 0.18
    static let shippingPerItem: Float = 10.0

    var products = [Product]()
    var discountRate: Float? = nil

    var orderValue: Float { products.compactMap { Float($0.price) }.reduce(0, +) }
    var tax: Float { Self.taxPercentage * orderValue }
    var shipping: Float { Self.shippingPerItem * Float(self.products.count) }
    var discount: Float? {
        guard let someRate = discountRate else {
            return nil
        }
        return -someRate * orderValue
    }
    var total: Float { orderValue + tax + shipping + (discount ?? 0) }
}
