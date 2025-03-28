/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI
import DatadogCore

/// A custom SwiftUI Hosting controller for `RootView`.
///
/// This definition only exist to allow instantiation from `RUMSwiftUIInstrumentationScenario`
/// storyboard and should be ignored from RUM instrumentation.
@available(iOS 13, *)
class SwiftUIRootViewController: UIHostingController<RootView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: RootView())
    }
}

/// The root view of the SwiftUI instrumentation test.
///
/// This view creates a  `SwiftUI.TabView` to present
/// navigation contexts..
@available(iOS 13, *)
struct RootView: View {
    var body: some View {
        TabView {
            tabNavigationView
                .tabItem {
                    Text("Navigation View")
                }

            tabScreenView
                .tabItem {
                    Text("Screen 100")
                }
        }
    }

    @ViewBuilder
    var tabNavigationView: some View {
        // An issue was introduced in iOS 14.2 (FB8907671) which makes
        // `TabView` items to be loaded twice, once when the `TabView`
        // appears` and once when the Tab item itself appears. This
        // lead to RUM views being reported twice. This issue seems to
        // have been fixed in iOS 15.
        // As a workaround, the tab view items can be embedded in a
        // `LazyVStack` or `LazyHStack` to lazily load its content when
        // it needs to render them onscreen.
        if #available(iOS 15, *) {
            NavigationView {
                ScreenView(index: 1)
            }
        } else if #available(iOS 14.2, *) {
            NavigationView {
                LazyVStack {
                    ScreenView(index: 1)
                }
            }
        } else {
            NavigationView {
                ScreenView(index: 1)
            }
        }
    }

    @ViewBuilder
    var tabScreenView: some View {
        if #available(iOS 15, *) {
            ScreenView(index: 100)
        } else if #available(iOS 14.2, *) {
            LazyVStack {
                ScreenView(index: 100)
            }
        } else {
            ScreenView(index: 100)
        }
    }
}

/// A basic Screen View at a given index in the stack.
///
/// This view presents a button to push a new view onto the
/// navigation stack, and a button to present a modal page sheet.
@available(iOS 13, *)
struct ScreenView: View {

    /// The view index in the stack.
    let index: Int

    @State private var presentSheet = false

    var body: some View {
        VStack(spacing: 32) {
            NavigationLink(
                "Push to Next View",
                destination: destination.dd_interactiveDismissDisabled()
            )
            .trackRUMTapAction(name: "Tap Push to Next View")

            Text("This is a Label")

            Button("Present Modal View") {
                presentSheet.toggle()
            }.trackRUMTapAction(name: "Tap Modal View")
        }
        .sheet(isPresented: $presentSheet) {
            NavigationView {
                destination
            }
        }
        .navigationBarTitle("Screen \(index)")
        .trackRUMView(name: "SwiftUI View \(index)")
    }

    @ViewBuilder
    var destination: some View {
        if index % 3 == 0  {
            UIScreenView(index: index + 1)
                .navigationBarTitle("Screen \(index + 1)")
        } else {
            ScreenView(index: index + 1)
        }
    }
}

/// The `UIScreenView` is a `UIScreenViewController` respresentable
/// for SwiftUI.
@available(iOS 13, *)
struct UIScreenView: UIViewControllerRepresentable {

    /// The screen index in the stack
    let index: Int

    func makeUIViewController(context: Context) -> UIScreenViewController {
        UIScreenViewController.create(at: index)
    }

    func updateUIViewController(_ uiViewController: UIScreenViewController, context: Context) { }
}

/// A basic Screen View Controller at a given index in the stack.
///
/// This view controller present a single button to push a
/// `ScreenView` onto the stack.
@available(iOS 13, *)
class UIScreenViewController: UIViewController {

    var index: Int = 0

    /// Creates a `UIScreenViewController` instance from `RUMSwiftUIInstrumentationScenario` storyboard.
    ///
    /// - Parameter index: The Screen index in the stack.
    /// - Returns: An instance of `UIScreenViewController`.
    static func create(at index: Int) -> UIScreenViewController {
        let storyboard = UIStoryboard(name: "RUMSwiftUIInstrumentationScenario", bundle: .main)

        if let vc = storyboard.instantiateViewController(withIdentifier: "UIScreenViewController") as? UIScreenViewController {
            vc.index = index
            return vc
        }

        fatalError("Unable to instantiate `UIScreenViewController` from stroyboard `RUMSwiftUIInstrumentationScenario`")
    }

    /// Pushes a `ScreenView` onto the stack.
    @IBAction func pushToSwiftUIView(_ sender: Any?) {
        let view = ScreenView(index: index + 1)
        let host = UIHostingController(rootView: view)
        navigationController?.show(host, sender: sender)
    }

    /// Pushes a `ScreenView` onto the stack.
    @IBAction func presentSheet(_ sender: Any?) {
        let host = UIHostingController(rootView: sheetView)
        host.modalPresentationStyle = .pageSheet
        present(host, animated: true)
    }

    @ViewBuilder
    var sheetView: some View {
        NavigationView {
            if index % 3 == 0  {
                UIScreenView(index: index + 1)
                    .navigationBarTitle("Screen \(index + 1)")
            } else {
                ScreenView(index: index + 1)
            }
        }
    }
}

@available(iOS 13, *)
extension View {
    func dd_interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        if #available(iOS 15.0, *) {
            return interactiveDismissDisabled(isDisabled)
        } else {
            return self
        }
    }
}

