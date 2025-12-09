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

    @available(iOS 15.0, tvOS 15.0, *)
    @Test("Test SwiftUI alerts, all button roles.", arguments: 1...5, 0...2)
    @MainActor
    func expectedControlTypesInAlertsSwiftUI(numberOfActionButtons: Int, numberOfTextFields: Int) throws {
        struct AlertTestView: View {
            let numberOfActionButtons: Int
            let numberOfTextFields: Int

            @State private var isAlertVisible = true

            let buttonRoles: [ButtonRole?] = {
                if #available(iOS 26, tvOS 26, *) {
                    return [nil, ButtonRole.cancel, .confirm, .destructive, .close]
                } else {
                    return [nil, ButtonRole.cancel, .destructive]
                }
            }()

            var body: some View {
                Text("")
                    .alert(String.mockRandom(), isPresented: $isAlertVisible) {
                        ForEach(0..<numberOfTextFields, id: \.self) { _ in
                            TextField(String.mockRandom(), text: .constant(.mockRandom()))
                        }

                        ForEach(0..<numberOfActionButtons, id: \.self) { i in
                            Button(String.mockRandom(), role: buttonRoles[min(i, buttonRoles.count - 1)]) { }
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

            let buttonRoles: [ButtonRole?] = {
                if #available(iOS 26, tvOS 26, *) {
                    return [ButtonRole.cancel, nil, .confirm, .destructive, .close]
                } else {
                    return [ButtonRole.cancel, nil, .destructive]
                }
            }()

            var body: some View {
                Text("")
                    .confirmationDialog(String.mockRandom(), isPresented: $isAlertVisible) {
                        ForEach(0..<numberOfActionButtons, id: \.self) { i in
                            Button(String.mockRandom(), role: buttonRoles[min(i, buttonRoles.count - 1)]) { }
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

        // There are multiple rules around buttons using .cancel role on confirmation dialogs:
        //   - iOS 26 will not show any .cancel button. The dialogs are displayed on a popover,
        //   and it's assumed clicking outside of the popover is the cancel action.
        //   - All previous versions of iOS, and all tvOS versions at the time of this writing
        //   will show only one .cancel button, even if there are multiple in the dialog.
        //
        // To test this properly, we add one (and only one) .cancel button as the first item of
        // the buttonRoles array above, guaranteeing all dialogs have one and only one .cancel
        // button. We also add a special way of handling iOS 26 below, since on that specific
        // iOS version, that button will be missing from the UI.
        let buttonCountOffset: Int
        #if os(iOS)
        if #available(iOS 26.0, *) {
            buttonCountOffset = -1
        } else {
            buttonCountOffset = 0
        }
        #else
        buttonCountOffset = 0
        #endif

        #expect(alertController.view.allSubviewsMatching(predicate: { $0.isUIAlertActionView }).count == numberOfActionButtons + buttonCountOffset)
    }
}
