import SwiftUI
import UIKit
import DatadogRUM

enum Route: String, Hashable { case detail }
@MainActor final class NavigationModel: ObservableObject {
    @Published var path: [Route] = [] { didSet { TransitionModel.path(path.map(\.rawValue)) } }
    @Published var selection: Route? { didSet {
        if selection != oldValue { TransitionModel.select(selection?.rawValue, occurrence: selection == nil ? nil : UUID().uuidString.lowercased()) }
    } }
    @Published var sheet = false { didSet { TransitionModel.sheet(sheet) } }
}
@main struct SwiftUIApp: App {
    @UIApplicationDelegateAdaptor(SwiftUIDelegate.self) var delegate
    @StateObject private var model = NavigationModel()
    var body: some Scene {
        WindowGroup {
            if Settings.layout == "split" { SplitScreen(model: model) }
            else { StackScreen(model: model) }
        }
    }
}
final class SwiftUIDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FixtureObservation.start(); return true
    }
}
struct StackScreen: View {
    @ObservedObject var model: NavigationModel
    var body: some View {
        NavigationStack(path: $model.path) {
            HomeScreen().navigationDestination(for: Route.self) { _ in DetailScreen(model: model) }
        }
    }
}
struct HomeScreen: View {
    var body: some View {
        Surface(screen: "home") {
            NavigationLink("Open detail", value: Route.detail).accessibilityIdentifier("home.next")
        }.navigationTitle("Home")
    }
}
struct DetailScreen: View {
    @ObservedObject var model: NavigationModel
    var body: some View {
        Surface(screen: "detail") {
            Button("Present sheet") { FixtureObservation.hit("detail.sheet"); model.sheet = true }
                .accessibilityIdentifier("detail.sheet")
            Button("Return home") {
                FixtureObservation.hit("detail.back")
                if Settings.layout == "split" { model.selection = nil } else { model.path.removeAll() }
            }.accessibilityIdentifier("detail.back")
        }.navigationTitle("Detail").sheet(isPresented: $model.sheet, onDismiss: {
            ObservationStore.shared.append("native_sheet_dismiss", ["request_id": HumanObservation.shared.currentRequestID ?? "nil"])
        }) { SheetScreen() }
    }
}
struct SheetScreen: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Surface(screen: "sheet") {
            Button("Dismiss sheet") { FixtureObservation.hit("sheet.close"); dismiss() }
                .accessibilityIdentifier("sheet.close")
        }
    }
}
struct SplitScreen: View {
    @ObservedObject var model: NavigationModel
    var body: some View {
        NavigationSplitView {
            Surface(screen: "sidebar") {
                List(selection: $model.selection) {
                    NavigationLink("Open detail", value: Route.detail).accessibilityIdentifier("sidebar.next")
                }.frame(height: 100)
            }.navigationTitle("Sidebar")
        } detail: {
            if model.selection == .detail { DetailScreen(model: model) }
            else { Surface(screen: "empty") { EmptyView() } }
        }
    }
}
struct Surface<Controls: View>: View {
    let screen: String
    @ViewBuilder var controls: () -> Controls
    var body: some View {
        VStack(spacing: 20) {
            if Settings.tracking == "manual" {
                Text(screen).accessibilityIdentifier("screen." + screen).trackRUMView(name: screen)
            } else { Text(screen).accessibilityIdentifier("screen." + screen) }
            controls()
        }.padding(24)
            .onAppear { FixtureObservation.appeared(screen) }
            .onDisappear { FixtureObservation.disappeared(screen) }
    }
}
