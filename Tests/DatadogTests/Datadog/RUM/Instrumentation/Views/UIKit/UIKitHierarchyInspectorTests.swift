/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UIKitHierarchyInspectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Non-modal presentation

    func testGivenNoRootViewController_itFindsNoTopVC() {
        // Given
        let inspector = UIKitHierarchyInspector { nil }

        // Then
        XCTAssertNil(inspector.topViewController())
    }

    func testGivenBasicViewControllerAsTheRoot_itFindsTopVC() {
        // Given
        let viewController = UIViewController()
        let inspector = UIKitHierarchyInspector { viewController }

        // Then
        XCTAssertTrue(inspector.topViewController() === viewController)
    }

    func testGivenNavigationControllerAsRoot_itFindsTopVC() {
        // Given
        let navigationController = UINavigationController()
        let inspector = UIKitHierarchyInspector { navigationController }

        // Then
        XCTAssertTrue(inspector.topViewController() === navigationController)
        navigationController.setViewControllers([UIViewController(), UIViewController()], animated: false)
        XCTAssertTrue(inspector.topViewController() === navigationController.viewControllers[1])
    }

    func testGivenTabBarControllerAsTheRoot_itFindsTopVC() {
        // Given
        let tabBarController = UITabBarController()
        let inspector = UIKitHierarchyInspector { tabBarController }

        // Then
        XCTAssertTrue(inspector.topViewController() === tabBarController)
        tabBarController.setViewControllers([UIViewController(), UIViewController()], animated: false)
        XCTAssertTrue(inspector.topViewController() === tabBarController.viewControllers![0])
    }

    func testGivenTabBarControllerAsTheRoot_whenItEmbedsNavigationControllerOnSecondTab_itFindsTopVC() {
        // Given
        let tabBarController = UITabBarController()
        let inspector = UIKitHierarchyInspector { tabBarController }

        // When
        let navigationController = UINavigationController()
        navigationController.setViewControllers([UIViewController(), UIViewController()], animated: false)
        tabBarController.setViewControllers([UIViewController(), navigationController], animated: false)
        tabBarController.selectedIndex = 1

        // Then
        XCTAssertTrue(inspector.topViewController() === navigationController.viewControllers[1])
    }

    // MARK: - Modal presentation

    func testGivenAnyVCAsTheRoot_whenNavigationControllerIsPresentedModally_itFindsTopVC() {
        // Given
        let anyViewController = [UINavigationController(), UITabBarController(), UIViewController()].randomElement()!
        let inspector = UIKitHierarchyInspector { anyViewController }

        // When
        let modalNavigationController = UINavigationController()
        modalNavigationController.setViewControllers([UIViewController(), UIViewController()], animated: false)

        let window = UIWindow(frame: .zero) // we need a window, so `.present()` doesn't throw an exception
        window.rootViewController = anyViewController
        window.makeKeyAndVisible()
        anyViewController.present(modalNavigationController, animated: false)

        // Then
        XCTAssertTrue(inspector.topViewController() === modalNavigationController.viewControllers[1])
    }
}
