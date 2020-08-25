/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

internal let cart = Cart()

extension Float {
    var moneyString: String { String(format: "€%.2f", self) }
}

internal final class Cart {
    static let taxPercentage: Float = 0.18
    static let shippingPerItem: Float = 10.0

    struct Breakdown {
        let products: [Product]
        let orderValue: Float
        let tax: Float
        let shipping: Float
        let discount: Float?
        let total: Float

        fileprivate init(products: [Product], discountRate: Float?) {
            self.products = products

            let tracer = Global.sharedTracer
            let mainSpan = tracer.startSpan(operationName: "Cart computation").setActive()

            let orderValueSpan = tracer.startSpan(operationName: "Order value computation")
            let orderValue = products.compactMap { Float($0.price) }.reduce(0, +)
            self.orderValue = orderValue
            orderValueSpan.setTag(key: "cart.orderValue", value: orderValue)
            Thread.sleep(for: .short)
            orderValueSpan.finish()

            let taxAndShippingSpan = tracer.startSpan(operationName: "Tax and shipping computation")
            tax = Cart.taxPercentage * orderValue
            shipping = Cart.shippingPerItem * Float(products.count)
            taxAndShippingSpan.setTag(key: "cart.tax", value: tax)
            taxAndShippingSpan.setTag(key: "cart.shipping", value: shipping)
            rum?.addViewError(message: "Tax&shipping cost cannot be calculated, default cost is used", source: .source, attributes: ["tax": tax, "shipping": shipping])
            Thread.sleep(for: .long)
            taxAndShippingSpan.finish()

            discount = {
                guard let someRate = discountRate else {
                    return nil
                }
                return -someRate * orderValue
            }()
            total = orderValue + tax + shipping + (discount ?? 0)
            mainSpan.setTag(key: "cart.total", value: total)
            mainSpan.finish()
        }
    }

    var products = [Product]()
    var discountRate: Float? = nil

    func generateBreakdown(completion: @escaping (Breakdown) -> Void) {
        DispatchQueue.global().async {
            let breakdown = Breakdown(products: self.products, discountRate: self.discountRate)
            DispatchQueue.main.async {
                completion(breakdown)
            }
        }
    }
}
