/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest

class ShopistUITests: XCTestCase {
    private func shouldContinueRunning(ifStartedAt startDate: Date) -> Bool {
        let targetRunDuration: TimeInterval = 27.5 * 60.0
        return Date().timeIntervalSince(startDate) < targetRunDuration
    }

    func testRunFullCheckoutFlow() {
        let startDate = Date()
        let app = ShopistApp()
        while shouldContinueRunning(ifStartedAt: startDate) {
            let categories = app.launchToHomepage()

            let targetItemCountInCart = Int.random(in: 1...2)
            var itemCount = 0
            while itemCount < targetItemCountInCart {
                do {
                    categories.swipeRandomly()
                    let products = try categories.goToProducts()
                    products.swipeRandomly()

                    let productDetails = try products.goToProductDetails()
                    if productDetails.addToCart() {
                        itemCount += 1
                    }
                    app.goBackToHomepage()

                    if itemCount == targetItemCountInCart {
                        let cart = try app.goToCart()
                        cart.checkout()
                        cart.proceed()
                    }
                } catch {
                    app.goBackToHomepage()
                }
            }
            app.terminate()
        }
        // Wait for uploading pending batches
        Thread.sleep(forTimeInterval: 15.0)
    }
}
