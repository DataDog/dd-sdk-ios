/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

let targetSessionCount = 10

class ShopistUITests: XCTestCase {
    func testRunFullCheckoutFlow() {
        let app = ShopistApp()
        for sessionIndex in 1...targetSessionCount {
            let categories = app.launchToHomepage()

            let targetItemCountInCart = Int.random(in: 1...5)
            var itemCount = 0
            while itemCount < targetItemCountInCart {
                do {
                    categories.swipeRandomly()
                    let products = try categories.goToProducts()
                    products.swipeRandomly()

                    let productDetails = try products.goToProductDetails()
                    if !productDetails.removeFromCart() {
                        productDetails.addToCart()
                        itemCount += 1
                    }
                    app.goBackToHomepage()

                    if itemCount == targetItemCountInCart {
                        let cart = try app.goToCart()
                        cart.checkout()
                        cart.proceed()

                        itemCount -= Int.random(in: 0...1)
                    }
                } catch {
                    app.goBackToHomepage()
                }
            }

            if sessionIndex == targetSessionCount {
                Thread.sleep(forTimeInterval: 15.0)
            }
            app.terminate()
        }
    }
}
