/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Testing
import UIKit
import TestUtilities
@testable import DatadogRUM
import SwiftUI

/// Tests our assumptions regarding the private view classes used by the operating systems when displaying alerts
/// and related dialogs, making sure our detectors are still valid in new OS versions.
///
/// Specifically:
///     - `UIView.isUIAlertActionView`
///     - `UIView.isUIAlertTextField`
///     - `UIViewController.isUIAlertController`
///
/// The tests are run for multiple combinations of the number of action buttons and, when it makes sense, number of
/// text fields in a dialog. Since Apple has been changing the layout of alerts often on multiple platforms depending on
/// the number of buttons, and their label size, we want to cover all the cases (horizontal vs vertical button stacking, etc)
/// just in case the classes used for those buttons change based on the layout differences.
///
/// We also want to test the different button styles and alert styles (alert VS action sheet/confirmation dialog) to cover
/// as many UI variations as possible.
@MainActor
struct UIKitExtensionsTests {
    private var mockAppWindow: UIWindow! // swiftlint:disable:this implicitly_unwrapped_optional

    init() {
        self.mockAppWindow = UIWindow(frame: .zero)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Tests UIKit alerts and action sheets, all button styles.", arguments: 1...5, 0...2)
    @MainActor
    func expectedControlTypesInAlerts(numberOfActionButtons: Int, numberOfTextFields: Int) throws {
        let hostViewController = UIViewController()
        mockAppWindow.rootViewController = hostViewController

        // Test all the button styles.
        let alertButtonStyles = [UIAlertAction.Style.cancel, .destructive, .default]

        [UIAlertController.Style.alert, .actionSheet].forEach { style in
            let alertController = UIAlertController(title: .mockRandom(), message: .mockRandom(), preferredStyle: style)

            for i in 0..<numberOfActionButtons {
                alertController.addAction(.init(title: .mockRandom(), style: alertButtonStyles[min(i, alertButtonStyles.count - 1)]))
            }

            if style == .alert {
                for _ in 0..<numberOfTextFields {
                    alertController.addTextField()
                }
            }

            hostViewController.present(alertController, animated: false)

            // Alert needs to be laid out otherwise the content is just not there.
            alertController.view.layoutIfNeeded()

            #expect(alertController.isUIAlertController)

            #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == numberOfActionButtons)

            if style == .alert {
                #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertTextField }).count == numberOfTextFields)
            }

            alertController.dismiss(animated: false)
        }
    }

    /// Obtains the available button roles, based on both the compile time and run time version checks.
    @available(iOS 15.0, tvOS 15.0, *)
    private static var buttonRoles: [ButtonRole?] {
        // We need to use both compile time and runtime checks for this,
        // to make sure we can build on Xcode <=16 (compile time check)
        // and run on <26 systems when building on Xcode >=26.
#if compiler(>=6.2)
        if #available(iOS 26, tvOS 26, *) {
            return [ButtonRole.cancel, nil, .confirm, .destructive, .close]
        } else {
            return [ButtonRole.cancel, nil, .destructive]
        }
#else
        return [nil, ButtonRole.cancel, .destructive]
#endif
    }

    /// Calculates the difference between expected buttons on most platforms and versions, and
    /// the specific case of iOS 26.
    ///
    /// There are multiple rules around buttons using `.cancel` role on confirmation dialogs:
    /// - iOS 26 will not show any `.cancel` button. The dialogs are displayed on a popover,
    ///   and it's assumed clicking outside of the popover is the cancel action.
    /// - All previous versions of iOS, and all tvOS versions at the time of this writing
    ///   will show only one `.cancel` button, even if there are multiple in the dialog.
    ///
    /// To test this properly, we add one (and only one) `.cancel` button as the first item of
    /// the buttonRoles array above, guaranteeing all dialogs have one and only one `.cancel`
    /// button. We also add a special way of handling iOS 26 below, since on that specific
    /// iOS version, that button will be missing from the UI.
    private var buttonCountOffset: Int {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return -1
        } else {
            return 0
        }
        #else
        return 0
        #endif
    }

    @available(iOS 15.0, tvOS 15.0, *)
    @Test("Test SwiftUI alerts, all button roles.", arguments: 1...5, 0...2)
    @MainActor
    func expectedControlTypesInAlertsSwiftUI(numberOfActionButtons: Int, numberOfTextFields: Int) throws {
        struct AlertTestView: View {
            let numberOfActionButtons: Int
            let numberOfTextFields: Int

            @State private var isAlertVisible = true

            var body: some View {
                Text("")
                    .alert(String.mockRandom(), isPresented: $isAlertVisible) {
                        ForEach(0..<numberOfTextFields, id: \.self) { _ in
                            TextField(String.mockRandom(), text: .constant(.mockRandom()))
                        }

                        ForEach(0..<numberOfActionButtons, id: \.self) { i in
                            Button(String.mockRandom(), role: UIKitExtensionsTests.buttonRoles[min(i, UIKitExtensionsTests.buttonRoles.count - 1)]) { }
                        }
                    }
            }
        }

        let hostViewController = UIHostingController(rootView: AlertTestView(numberOfActionButtons: numberOfActionButtons, numberOfTextFields: numberOfTextFields))
        mockAppWindow.rootViewController = hostViewController

        mockAppWindow.makeKeyAndVisible()
        mockAppWindow.layoutIfNeeded()

        let alertController = try #require(hostViewController.presentedViewController)

        // Alert needs to be laid out otherwise the content is just not there.
        alertController.view.layoutIfNeeded()

        #expect(alertController.isUIAlertController)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == numberOfActionButtons)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertTextField }).count == numberOfTextFields)
    }

    @available(iOS 15.0, tvOS 15.0, *)
    @Test("Test SwiftUI confirmation dialogs, all button roles.", arguments: 1...5)
    @MainActor
    func expectedControlTypesInConfirmationDialogsSwiftUI(numberOfActionButtons: Int) throws {
        struct ConfirmationDialogTestView: View {
            let numberOfActionButtons: Int

            @State private var isAlertVisible = true

            var body: some View {
                Text("")
                    .confirmationDialog(String.mockRandom(), isPresented: $isAlertVisible) {
                        ForEach(0..<numberOfActionButtons, id: \.self) { i in
                            Button(String.mockRandom(), role: UIKitExtensionsTests.buttonRoles[min(i, UIKitExtensionsTests.buttonRoles.count - 1)]) { }
                        }
                    }
            }
        }

        let hostViewController = UIHostingController(rootView: ConfirmationDialogTestView(numberOfActionButtons: numberOfActionButtons))
        mockAppWindow.rootViewController = hostViewController

        mockAppWindow.makeKeyAndVisible()
        mockAppWindow.layoutIfNeeded()

        let alertController = try #require(hostViewController.presentedViewController)

        // Alert needs to be laid out otherwise the content is just not there.
        alertController.view.layoutIfNeeded()

        #expect(alertController.isUIAlertController)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == numberOfActionButtons + buttonCountOffset)
    }

    // MARK: Tests for old style alerts and action sheets (iOS/tvOS 13.0-14.*)

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Test SwiftUI deprecated Alert constructor.")
    @MainActor
    func expectedControlTypesInDeprecatedAlertsSwiftUI() throws {
        struct AlertTestView: View {
            @State private var isAlertVisible = true

            var body: some View {
                Text("")
                    .alert(isPresented: $isAlertVisible) {
                        Alert(
                            title: Text(String.mockRandom()),
                            message: Text(String.mockRandom()),
                            primaryButton: .default(Text(String.mockRandom())),
                            secondaryButton: .cancel(Text(String.mockRandom()))
                        )
                    }
            }
        }

        let hostViewController = UIHostingController(rootView: AlertTestView())
        mockAppWindow.rootViewController = hostViewController

        mockAppWindow.makeKeyAndVisible()
        mockAppWindow.layoutIfNeeded()

        let alertController = try #require(hostViewController.presentedViewController)

        // Alert needs to be laid out otherwise the content is just not there.
        alertController.view.layoutIfNeeded()

        #expect(alertController.isUIAlertController)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == 2)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertTextField }).count == 0)
    }

    @available(iOS 15.0, tvOS 15.0, *)
    @Test("Test SwiftUI deprecated ActionSheet constructor, all button roles.", arguments: 1...5)
    @MainActor
    func expectedControlTypesInDeprecatedActionSheetsSwiftUI(numberOfActionButtons: Int) throws {
        struct ActionSheetTestView: View {
            let numberOfActionButtons: Int

            @State private var isAlertVisible = true

            let buttonConstructors: [(Text, @escaping (() -> Void)) -> Alert.Button] = [Alert.Button.cancel, Alert.Button.default, Alert.Button.destructive]

            var body: some View {
                Text("")
                    .actionSheet(isPresented: $isAlertVisible) {
                        ActionSheet(
                            title: Text(String.mockRandom()),
                            message: Text(String.mockRandom()),
                            buttons: (1...numberOfActionButtons).map { n in
                                let constructor = buttonConstructors[min(n - 1, buttonConstructors.count - 1)]
                                return constructor(Text(String.mockRandom()), { })
                            }
                        )
                    }
            }
        }

        let hostViewController = UIHostingController(rootView: ActionSheetTestView(numberOfActionButtons: numberOfActionButtons))
        mockAppWindow.rootViewController = hostViewController

        mockAppWindow.makeKeyAndVisible()
        mockAppWindow.layoutIfNeeded()

        let alertController = try #require(hostViewController.presentedViewController)

        // Alert needs to be laid out otherwise the content is just not there.
        alertController.view.layoutIfNeeded()

        #expect(alertController.isUIAlertController)

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == numberOfActionButtons + buttonCountOffset)
    }
}
