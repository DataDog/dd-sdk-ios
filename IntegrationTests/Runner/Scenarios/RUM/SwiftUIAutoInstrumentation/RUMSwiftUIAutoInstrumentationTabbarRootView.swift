
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI
import DatadogRUM

// MARK: - SwiftUIAutoInstrumentationTabbarRootView

@available(iOS 16.0, *)
class SwiftUIAutoInstrumentationTabbarRootView: UIHostingController<RootTabView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: RootTabView())
    }
}

// MARK: - RootTabView

@available(iOS 16.0, *)
struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationViewExample()
                .tabItem {
                    Label("Navigation View", systemImage: "arrow.right.square")
                }

            NavigationStackExample()
                .tabItem {
                    Label("Navigation Stack", systemImage: "square.stack")
                }

            NavigationSplitExample()
                .tabItem {
                    Label("Navigation Split", systemImage: "rectangle.split.3x1")
                }

            ModalExample()
                .tabItem {
                    Label("Modals", systemImage: "menubar.arrow.up.rectangle")
                }
                .trackRUMView(name: "Modal Tab")
        }
    }
}

// MARK: NavigationView

@available(iOS 16.0, *)
struct NavigationViewExample: View {
    var body: some View {
        NavigationView {
            List {
                // Simple detail items
                Section(header: Text("Simple Navigation")) {
                    ForEach(1...3, id: \.self) { number in
                        NavigationLink(destination: NumberDetailView(number: number)) {
                            Text("Item \(number)")
                        }
                    }
                }

                // Nested navigation section
                Section(header: Text("Nested Navigation")) {
                    ForEach(1...2, id: \.self) { category in
                        NavigationLink(destination: CategoryDetailView(category: category)) {
                            Text("Category \(category)")
                        }
                    }
                }
            }
            .navigationTitle("Navigation View")
        }
    }
}

// MARK: NavigationStack

@available(iOS 16.0, *)
struct NavigationStackExample: View {
    let items = ["Apple", "Banana", "Cherry"]

    var body: some View {
        NavigationStack {
            List {
                // Simple detail items
                Section(header: Text("Simple Navigation")) {
                    ForEach(1...3, id: \.self) { number in
                        NavigationLink(destination: NumberDetailView(number: number)) {
                            Text("Item \(number)")
                        }
                    }
                }

                // Nested navigation section
                Section(header: Text("Nested Navigation")) {
                    ForEach(1...2, id: \.self) { category in
                        NavigationLink(destination: CategoryDetailView(category: category)) {
                            Text("Category \(category)")
                        }
                    }
                }
            }
            .navigationTitle("Navigation Stack")
        }
    }
}

// MARK: NavigationSplitView

@available(iOS 16.0, *)
struct NavigationSplitExample: View {
    @State private var selectedItem: Int? = nil

    var body: some View {
        NavigationSplitView {
            List(1...5, id: \.self, selection: $selectedItem) { number in
                Text("Item \(number)")
                    .tag(number)
            }
            .navigationTitle("Navigation Split")
        } detail: {
            if let item = selectedItem,
               (1...4).contains(item) {
                NumberDetailView(number: item)
            } else {
                PlaceholderView()
            }
        }
    }
}

// MARK: Modal

@available(iOS 14.0, *)
struct ModalExample: View {
    @State private var showSheet = false
    @State private var showFullScreen = false

    var body: some View {
        VStack(spacing: 20) {
            Button("Show Sheet") {
                showSheet.toggle()
            }
            .sheet(isPresented: $showSheet) {
                ModalSheet(type: "Sheet", onDismiss: { showSheet = false })
            }

            Button("Show FullScreenCover") {
                showFullScreen.toggle()
            }
            .fullScreenCover(isPresented: $showFullScreen) {
                ModalSheet(type: "Full Screen Cover", onDismiss: { showFullScreen = false })
            }
        }
        .navigationTitle("Modals")
    }
}

// MARK: Detail views

@available(iOS 14.0, *)
struct CategoryDetailView: View {
    let category: Int

    var body: some View {
        List(1...4, id: \.self) { item in
            NavigationLink(destination: ItemDetailView(category: category, item: item)) {
                Text("Category \(category) - Item \(item)")
            }
        }
    }
}

@available(iOS 14.0, *)
struct ItemDetailView: View {
    let category: Int
    let item: Int

    var body: some View {
        VStack(spacing: 20) {
            Text("Category \(category)")
                .font(.headline)
            Text("Item \(item) Details")
                .font(.largeTitle)
        }
    }
}

@available(iOS 14.0, *)
struct NumberDetailView: View {
    let number: Int

    var body: some View {
        Text("Details for Item \(number)")
            .font(.largeTitle)
    }
}

@available(iOS 13.0, *)
struct PlaceholderView: View {
    var body: some View {
        Text("Wrong item selected")
            .font(.title)
            .foregroundColor(.gray)
    }
}

@available(iOS 13.0, *)
struct ModalSheet: View {
    let type: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack {
            Text("This is a \(type)")
                .padding()

            Button("Close") {
                onDismiss?()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
}
