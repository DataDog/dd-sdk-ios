/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import SwiftUI
import Datadog

@available(iOS 13, *)
/// A custom SwiftUI Hosting controller for `RootView`.
///
/// This definition only exist to allow instantiation from `RUMSwiftUIInstrumentationScenario`
/// storyboard and should be ignored from RUM instrumentation.
class SwiftUIRootViewController: UIHostingController<RootView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: RootView())
    }
}

@available(iOS 13, *)
/// The root view of the SwiftUI instrumentation test.
///
/// This view creates a navigation stack and present a`ScreenView` as fist view.
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
        // lead to RUM views being reported twice. This issue was fixed
        // in iOS 14.5, see https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-14_5-release-notes
        // As a workaround, the tab view items can be embedded in a
        // `LazyVStack` or `LazyHStack` to lazily load its content when
        // it needs to render them onscreen.
        if #available(iOS 14.5, *) {
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
        if #available(iOS 14.5, *) {
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

@available(iOS 13, *)
/// A basic Screen View at a given index in the stack.
///
/// This view presents a single navigation button to push a
/// `UIScreenView` onto the stack.
struct ScreenView: View {

    /// The view index in the stack.
    let index: Int

    @State private var presentSheet = false

    var body: some View {
        VStack(spacing: 32) {
            NavigationLink("Push to Next View", destination:
                ScreenView(index: index + 1)
            )
            Button("Present Modal View") {
                presentSheet.toggle()
            }
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
        ScreenView(index: index + 1)
    }
}
