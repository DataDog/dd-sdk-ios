/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

struct NavigationError: LocalizedError {
    let origin: String
    var localizedDescription: String { "\(origin) cannot proceed to the next page!" }
}

class ShopistApp: XCUIApplication {
    func launchToHomepage() -> CategoriesPage {
        self.launch()
        return CategoriesPage()
    }

    func goToCart() throws -> CartPage {
        if navBar.buttons["cart"].safeTap() {
            return CartPage()
        }
        throw NavigationError(origin: "App->Cart")
    }

    func goBackToHomepage() {
        let backButton = navBar.buttons["back"]
        while backButton.safeTap() {
            continue
        }
    }
}

class CategoriesPage: XCUIApplication {
    func goToProducts() throws -> ProductsPage {
        if tapRandomCell() {
            return ProductsPage()
        }
        throw NavigationError(origin: "Categories->Products")
    }
}

class ProductsPage: XCUIApplication {
    func goToProductDetails() throws -> ProductDetailsPage {
        if tapRandomCell() {
            return ProductDetailsPage()
        }
        throw NavigationError(origin: "Products->Detail")
    }
}

class ProductDetailsPage: XCUIApplication {
    func addToCart() -> Bool {
        if navBar.buttons["addToCart"].exists {
            navBar.buttons["addToCart"].safeTap()
            return true
        }
        return false
    }

    func removeFromCart() -> Bool {
        return navBar.buttons["removeFromCart"].safeTap()
    }
}

class CartPage: XCUIApplication {
    func checkout() {
        navigationBars["Cart"].buttons["pay"].safeTap(within: 3.0)
    }

    func proceed() {
        alerts.firstMatch.buttons.firstMatch.safeTap(within: 30.0)
    }
}

extension XCUIApplication {
    var navBar: XCUIElement { navigationBars.firstMatch }

    func swipeRandomly() {
        let swipeCount = UInt8.random(in: 0...2)
        (0...swipeCount).forEach { _ in
            if UInt8.random(in: 0...3) == 0 {
                self.swipeDown()
            } else {
                self.swipeUp()
            }
        }
    }

    func tapRandomCell() -> Bool {
        var cells = collectionViews.cells.allElementsBoundByIndex
        while let randomIndex = cells.indices.randomElement() {
            let randomCell = cells[randomIndex]
            if randomCell.safeTap() {
                return true
            } else {
                cells.remove(at: randomIndex)
            }
        }
        return false
    }
}

extension XCUIElement {
    @discardableResult
    func safeTap(within timeout: TimeInterval = 0) -> Bool {
        if waitForExistence(timeout: timeout) && isHittable {
            tap()
            return true
        }
        return false
    }
}
