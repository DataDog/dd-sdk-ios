/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI
import DatadogRUM
import DatadogTrace

struct RUMMultiSceneProbeSwiftUIRoot: View {
    let context: RUMMultiSceneProbeContext

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    RUMMultiSceneProbeSwiftUIScreen(
                        context: context,
                        screen: .home(depth: 0)
                    )
                }
            } else {
                NavigationView {
                    RUMMultiSceneProbeSwiftUIScreen(
                        context: context,
                        screen: .home(depth: 0)
                    )
                }
                .navigationViewStyle(.stack)
            }
        }
        .accessibilityIdentifier("probe.swiftui.root.\(context.sceneLabel)")
    }
}

private struct RUMMultiSceneProbeSwiftUIScreen: View {
    enum Screen {
        case home(depth: Int)
        case detail(depth: Int)
        case shared
        case modal

        var title: String {
            switch self {
            case .home(let depth):
                return depth == 0 ? "Home" : "Detail \(depth)"
            case .detail(let depth):
                return "Detail \(depth)"
            case .shared:
                return "Shared Detail"
            case .modal:
                return "Modal"
            }
        }

        var pathComponent: String {
            switch self {
            case .home(let depth):
                return depth == 0 ? "home" : "detail-\(depth)"
            case .detail(let depth):
                return "detail-\(depth)"
            case .shared:
                return "shared-detail"
            case .modal:
                return "modal"
            }
        }

        var depth: Int {
            switch self {
            case .home(let depth), .detail(let depth):
                return depth
            case .shared, .modal:
                return 0
            }
        }
    }

    let context: RUMMultiSceneProbeContext
    let screen: Screen

    @State private var isModalPresented = false
    @State private var status = "Ready"
    @State private var didStartOnAppearRequest = false
    @State private var didStartTaskRequest = false

    private var rumViewName: String {
        switch screen {
        case .shared:
            return "SwiftUI Shared Detail"
        default:
            return "SwiftUI \(context.sceneLabel) \(screen.title)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("RUM multi-scene probe")
                    .font(.title2)
                Text("run: \(context.runID)")
                Text("source: \(context.sceneLabel)")
                Text("native session: \(context.sceneSessionID)")
                Text("view: \(rumViewName)")
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("probe.swiftui.status.\(context.sceneLabel)")

                Button("Open another window") {
                    mark("requested another window")
                    RUMMultiSceneProbeState.requestNewScene(after: context)
                }
                .accessibilityIdentifier(identifier("open-window"))

                Button("Activate other window") {
                    mark("requested other window activation")
                    RUMMultiSceneProbeState.activateOtherScene(from: context)
                }
                .accessibilityIdentifier(identifier("activate-other-window"))

                Button("Close this window") {
                    mark("requested scene close")
                    RUMMultiSceneProbeState.closeScene(context: context)
                }
                .accessibilityIdentifier(identifier("close-window"))

                NavigationLink {
                    RUMMultiSceneProbeSwiftUIScreen(
                        context: context,
                        screen: .detail(depth: screen.depth + 1)
                    )
                } label: {
                    Text("Push SwiftUI detail")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .trackRUMTapAction(
                    name: "swiftui-push-detail-\(context.sceneLabel)",
                    attributes: attributes(origin: "swiftui-navigation")
                )
                .accessibilityIdentifier(identifier("push-detail"))

                NavigationLink {
                    RUMMultiSceneProbeSwiftUIScreen(context: context, screen: .shared)
                } label: {
                    Text("Push duplicate-name view")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .trackRUMTapAction(
                    name: "swiftui-push-shared-\(context.sceneLabel)",
                    attributes: attributes(origin: "swiftui-navigation-shared")
                )
                .accessibilityIdentifier(identifier("push-shared"))

                Button("Present SwiftUI modal") {
                    mark("present modal")
                    isModalPresented = true
                }
                .accessibilityIdentifier(identifier("present-modal"))

                Button("Automatic tap marker") {
                    mark("automatic tap handler")
                }
                .accessibilityIdentifier(identifier("automatic-tap"))

                Button("Manual RUM tap action") {
                    mark("manual tap handler")
                }
                .trackRUMTapAction(
                    name: "swiftui-manual-tap-\(context.sceneLabel)",
                    attributes: attributes(origin: "swiftui-manual-tap")
                )
                .accessibilityIdentifier(identifier("manual-action"))

                Button("Start 3s RUM resource") {
                    startResource()
                }
                .accessibilityIdentifier(identifier("resource"))

                Button("URLSession synchronous") {
                    mark("URLSession synchronous")
                    RUMMultiSceneProbeState.startNetworkRequest(
                        context: context,
                        networkCase: "swiftui-sync"
                    )
                }
                .accessibilityIdentifier(identifier("network-sync"))

                Button("URLSession in Task within action window") {
                    mark("URLSession structured task scheduled within action window")
                    Task { [context] in
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        RUMMultiSceneProbeState.startNetworkRequest(
                            context: context,
                            networkCase: "swiftui-task-within-action-window"
                        )
                    }
                }
                .accessibilityIdentifier(identifier("network-task"))

                Button("URLSession in Task after action expiry") {
                    mark("URLSession structured task scheduled after action expiry")
                    Task { [context] in
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        RUMMultiSceneProbeState.startNetworkRequest(
                            context: context,
                            networkCase: "swiftui-task-after-action-expiry"
                        )
                    }
                }
                .accessibilityIdentifier(identifier("network-task-expired"))

                Button("Start trace-only URLSession") {
                    mark("trace-only URLSession started")
                    RUMMultiSceneProbeState.startNetworkRequest(
                        context: context,
                        networkCase: "swiftui-trace-only",
                        traceOnly: true
                    )
                }
                .accessibilityIdentifier(identifier("network-trace-only"))

                Button("Use shared URLSession request") {
                    mark("shared URLSession requested")
                    RUMMultiSceneProbeState.useSharedNetworkRequest(context: context)
                }
                .accessibilityIdentifier(identifier("network-shared"))

                Button("Send RUM error") {
                    mark("manual error")
                    RUMMonitor.shared().addError(
                        message: "probe-error-\(context.sceneLabel)",
                        source: .source,
                        attributes: attributes(origin: "swiftui-error")
                    )
                }
                .accessibilityIdentifier(identifier("error"))

                Button("Send correlated log") {
                    mark("correlated log")
                    logger?.info(
                        "probe-log-\(context.sceneLabel)",
                        attributes: attributes(origin: "swiftui-log")
                    )
                }
                .accessibilityIdentifier(identifier("log"))

                Button("Start 3s trace span") {
                    startTrace()
                }
                .accessibilityIdentifier(identifier("trace"))

                Button("Start 3s feature operation") {
                    startOperation()
                }
                .accessibilityIdentifier(identifier("operation"))

                Button("Block main thread for 250ms") {
                    mark("long task started")
                    Thread.sleep(forTimeInterval: 0.25)
                    mark("long task finished")
                }
                .accessibilityIdentifier(identifier("long-task"))

                ForEach(1...20, id: \.self) { index in
                    Text("Scroll marker \(index) — \(context.sceneLabel)")
                        .foregroundStyle(.secondary)
                        .frame(height: 30)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("\(context.sceneLabel): \(screen.title)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    mark("requested scene close from toolbar")
                    RUMMultiSceneProbeState.closeScene(context: context)
                }
                .accessibilityIdentifier(identifier("close-window-toolbar"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Other Window") {
                    mark("requested other window activation from toolbar")
                    RUMMultiSceneProbeState.activateOtherScene(from: context)
                }
                .accessibilityIdentifier(identifier("activate-other-window-toolbar"))
            }
        }
        .sheet(isPresented: $isModalPresented) {
            NavigationView {
                RUMMultiSceneProbeSwiftUIScreen(context: context, screen: .modal)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Dismiss") {
                                isModalPresented = false
                            }
                            .accessibilityIdentifier(identifier("dismiss-modal"))
                        }
                    }
            }
        }
        .trackRUMView(
            name: rumViewName,
            attributes: context.attributes
        )
        .accessibilityIdentifier(
            "probe.swiftui.\(context.sceneLabel).\(screen.pathComponent)"
        )
        .onAppear {
            guard !didStartOnAppearRequest else {
                return
            }
            didStartOnAppearRequest = true
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "swiftui-on-appear-\(screen.pathComponent)",
                delay: 0.25
            )
        }
        .task {
            guard !didStartTaskRequest else {
                return
            }
            didStartTaskRequest = true
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "swiftui-task-immediate-\(screen.pathComponent)",
                delay: 0.25
            )
            await Task.yield()
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else {
                return
            }
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "swiftui-task-modifier-\(screen.pathComponent)",
                delay: 0.25
            )
        }
    }

    private func identifier(_ suffix: String) -> String {
        "probe.swiftui.\(context.sceneLabel).\(suffix)"
    }

    private func attributes(origin: String) -> [String: Encodable] {
        var attributes = context.attributes
        attributes[RUMMultiSceneProbeState.Attribute.origin] = origin
        return attributes
    }

    private func mark(_ message: String) {
        status = message
        RUMMultiSceneProbeState.record(
            "control source=\(context.sceneLabel) screen=swiftui-\(screen.pathComponent) \(message)"
        )
    }

    private func startResource() {
        let key = "resource-swiftui-\(context.sceneLabel)-\(UUID().uuidString)"
        let url = URL(
            string: "https://multi-scene-probe.invalid/\(context.sceneLabel)/\(key)"
        )!
        mark("resource started key=\(key)")
        RUMMonitor.shared().startResource(
            resourceKey: key,
            url: url,
            attributes: attributes(origin: "swiftui-resource-start")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [context] in
            RUMMonitor.shared().stopResource(
                resourceKey: key,
                statusCode: 200,
                kind: .other,
                size: 128,
                attributes: [
                    RUMMultiSceneProbeState.Attribute.runID: context.runID,
                    RUMMultiSceneProbeState.Attribute.sourceScene: context.sceneLabel,
                    RUMMultiSceneProbeState.Attribute.sceneSessionID: context.sceneSessionID,
                    RUMMultiSceneProbeState.Attribute.origin: "swiftui-resource-stop"
                ]
            )
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) swiftui resource finished key=\(key)"
            )
        }
    }

    private func startTrace() {
        mark("trace started")
        let span = Tracer.shared().startSpan(
            operationName: "probe-span-swiftui-\(context.sceneLabel)"
        )
        span.setTag(key: RUMMultiSceneProbeState.Attribute.runID, value: context.runID)
        span.setTag(
            key: RUMMultiSceneProbeState.Attribute.sourceScene,
            value: context.sceneLabel
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [context] in
            span.finish()
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) swiftui trace finished"
            )
        }
    }

    private func startOperation() {
        let operationKey = UUID().uuidString
        mark("operation started key=\(operationKey)")
        RUMMonitor.shared().startOperation(
            name: "probe-operation",
            operationKey: operationKey,
            attributes: attributes(origin: "swiftui-operation-start")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [context] in
            RUMMonitor.shared().succeedOperation(
                name: "probe-operation",
                operationKey: operationKey,
                attributes: [
                    RUMMultiSceneProbeState.Attribute.runID: context.runID,
                    RUMMultiSceneProbeState.Attribute.sourceScene: context.sceneLabel,
                    RUMMultiSceneProbeState.Attribute.sceneSessionID: context.sceneSessionID,
                    RUMMultiSceneProbeState.Attribute.origin: "swiftui-operation-stop"
                ]
            )
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) swiftui operation finished key=\(operationKey)"
            )
        }
    }
}
