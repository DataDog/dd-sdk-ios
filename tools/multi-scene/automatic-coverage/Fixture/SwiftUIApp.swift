import SwiftUI
import UIKit

@main struct SwiftUIApp: App {
    @UIApplicationDelegateAdaptor(SwiftUIDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            if Settings.layout == "split" { AutomaticSplit() }
            else { AutomaticStack() }
        }
    }
}
final class SwiftUIDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FixtureObservation.start(); return true
    }
}
struct AutomaticStack: View {
    var body: some View {
        NavigationStack { HomeScreen() }
    }
}
struct HomeScreen: View {
    var body: some View {
        Surface(screen: "home") {
            NavigationLink("Open detail") { DetailScreen() }.accessibilityIdentifier("home.next")
        }.navigationTitle("Home")
    }
}
struct DetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sheet = false
    var onBack: (() -> Void)?
    var body: some View {
        Surface(screen: "detail") {
            Button("Present sheet") { FixtureObservation.hit("detail.sheet"); sheet = true }.accessibilityIdentifier("detail.sheet")
            Button("Return home") { FixtureObservation.hit("detail.back"); onBack?(); dismiss() }.accessibilityIdentifier("detail.back")
        }.navigationTitle("Detail").sheet(isPresented: $sheet) { SheetScreen() }
    }
}
struct SheetScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Surface(screen: "sheet") {
            Button("Dismiss sheet") { FixtureObservation.hit("sheet.close"); dismiss() }.accessibilityIdentifier("sheet.close")
        }
    }
}
struct AutomaticSplit: View {
    @State private var selection: String?
    var body: some View {
        NavigationSplitView {
            Surface(screen: "sidebar") {
                List(selection: $selection) {
                    NavigationLink("Open detail", value: "detail").accessibilityIdentifier("sidebar.next")
                }.frame(height: 80)
            }.navigationTitle("Sidebar")
        } detail: {
            if selection != nil { DetailScreen(onBack: { selection = nil }) }
            else { Surface(screen: "empty") { EmptyView() } }
        }
    }
}
struct Surface<Controls: View>: View {
    let screen: String
    @ViewBuilder var controls: () -> Controls
    @State private var count = 0
    @State private var enabled = false
    var body: some View {
        VStack(spacing: 8) {
            Text(screen).accessibilityIdentifier("screen." + screen)
            Button("Tap") { FixtureObservation.hit(screen + ".tap"); count += 1 }.accessibilityIdentifier(screen + ".tap")
            controls()
            Toggle("Enable", isOn: $enabled).accessibilityIdentifier(screen + ".toggle")
                .onChange(of: enabled) { _ in FixtureObservation.hit(screen + ".toggle"); count += 1 }
            ScrollView {
                VStack { ForEach(0..<30) { Text("Row \($0)").frame(height: 30) } }
            }.frame(height: 150).accessibilityIdentifier(screen + ".scroll")
            Text("receipt:\(count)").accessibilityIdentifier(screen + ".receipt")
        }.padding(16).onAppear { FixtureObservation.appeared(screen) }
    }
}
