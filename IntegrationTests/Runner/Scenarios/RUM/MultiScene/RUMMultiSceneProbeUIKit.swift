/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import SwiftUI
import DatadogRUM
import DatadogTrace

final class RUMMultiSceneProbeRootViewController: UITabBarController {
    private let context: RUMMultiSceneProbeContext

    init(context: RUMMultiSceneProbeContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)

        let uiKitRoot = RUMMultiSceneProbeUIKitViewController(
            context: context,
            screen: .home(depth: 0)
        )
        let uiKitNavigation = UINavigationController(rootViewController: uiKitRoot)
        uiKitNavigation.tabBarItem = UITabBarItem(
            title: "UIKit",
            image: UIImage(systemName: "rectangle.3.group"),
            tag: 0
        )

        let swiftUIRoot = UIHostingController(
            rootView: RUMMultiSceneProbeSwiftUIRoot(context: context)
        )
        swiftUIRoot.tabBarItem = UITabBarItem(
            title: "SwiftUI",
            image: UIImage(systemName: "swift"),
            tag: 1
        )

        viewControllers = [uiKitNavigation, swiftUIRoot]
        view.accessibilityIdentifier = "probe.root.\(context.sceneLabel)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class RUMMultiSceneProbeUIKitViewController:
    UIViewController,
    RUMMultiSceneProbeViewDescribing
{
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

    var rumViewName: String {
        switch screen {
        case .shared:
            return "UIKit Shared Detail"
        default:
            return "UIKit \(context.sceneLabel) \(screen.title)"
        }
    }

    var rumViewPath: String {
        "/multi-scene-probe/\(context.sceneLabel)/uikit/\(screen.pathComponent)"
    }

    private let statusLabel = UILabel()
    private var didStartViewDidAppearRequest = false

    init(context: RUMMultiSceneProbeContext, screen: Screen) {
        self.context = context
        self.screen = screen
        super.init(nibName: nil, bundle: nil)
        title = "\(context.sceneLabel): \(screen.title)"

        let activateOtherWindowItem = UIBarButtonItem(
            title: "Other Window",
            style: .plain,
            target: self,
            action: #selector(activateOtherWindow)
        )
        activateOtherWindowItem.accessibilityIdentifier =
            "probe.\(context.sceneLabel).activate-other-window-toolbar"
        navigationItem.rightBarButtonItem = activateOtherWindowItem

        let closeWindowItem = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(closeWindow)
        )
        closeWindowItem.accessibilityIdentifier =
            "probe.\(context.sceneLabel).close-window-toolbar"
        navigationItem.leftBarButtonItem = closeWindowItem
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "probe.uikit.\(context.sceneLabel).\(screen.pathComponent)"
        configureContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartViewDidAppearRequest else {
            return
        }
        didStartViewDidAppearRequest = true
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "uikit-view-did-appear-\(screen.pathComponent)",
            delay: 0.25
        )
    }

    private func configureContent() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "probe.scroll.\(context.sceneLabel)"
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let heading = UILabel()
        heading.numberOfLines = 0
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.text = """
        RUM multi-scene probe
        run: \(context.runID)
        source: \(context.sceneLabel)
        native session: \(context.sceneSessionID)
        view: \(rumViewName)
        """
        heading.accessibilityIdentifier = "probe.heading.\(context.sceneLabel)"
        stack.addArrangedSubview(heading)

        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Ready"
        statusLabel.accessibilityIdentifier = "probe.status.\(context.sceneLabel)"
        stack.addArrangedSubview(statusLabel)

        if case .modal = screen {
            stack.addArrangedSubview(
                button(title: "Dismiss modal", id: "dismiss-modal", action: #selector(dismissModal))
            )
        }

        stack.addArrangedSubview(
            button(title: "Open another window", id: "open-window", action: #selector(openWindow))
        )
        stack.addArrangedSubview(
            button(
                title: "Activate other window",
                id: "activate-other-window",
                action: #selector(activateOtherWindow)
            )
        )
        stack.addArrangedSubview(
            button(title: "Close this window", id: "close-window", action: #selector(closeWindow))
        )
        stack.addArrangedSubview(
            button(title: "Push UIKit detail", id: "push-detail", action: #selector(pushDetail))
        )
        stack.addArrangedSubview(
            button(title: "Push duplicate-name view", id: "push-shared", action: #selector(pushSharedDetail))
        )
        stack.addArrangedSubview(
            button(title: "Present UIKit modal", id: "present-modal", action: #selector(presentModal))
        )
        stack.addArrangedSubview(
            button(title: "Automatic tap marker", id: "automatic-tap", action: #selector(automaticTap))
        )
        stack.addArrangedSubview(
            button(title: "Manual RUM action", id: "manual-action", action: #selector(manualAction))
        )
        stack.addArrangedSubview(
            button(title: "Start 3s RUM resource", id: "resource", action: #selector(startResource))
        )
        stack.addArrangedSubview(
            button(title: "URLSession synchronous", id: "network-sync", action: #selector(startSynchronousNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession in Task within action window", id: "network-task", action: #selector(startStructuredTaskNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession in Task after action expiry", id: "network-task-expired", action: #selector(startExpiredStructuredTaskNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession in Task after scene switch", id: "network-task-scene-switch", action: #selector(startSceneSwitchStructuredTaskNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession in detached task", id: "network-detached", action: #selector(startDetachedTaskNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession on DispatchQueue", id: "network-gcd", action: #selector(startGCDNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession from Timer", id: "network-timer", action: #selector(startTimerNetwork))
        )
        stack.addArrangedSubview(
            button(title: "URLSession with filtered action", id: "filtered-network", action: #selector(startFilteredActionNetwork))
        )
        stack.addArrangedSubview(
            button(title: "Create URLSession task", id: "network-create", action: #selector(createNetworkTask))
        )
        stack.addArrangedSubview(
            button(title: "Resume pre-created task", id: "network-resume", action: #selector(resumeNetworkTask))
        )
        stack.addArrangedSubview(
            button(title: "Task across session rollover", id: "network-session-rollover", action: #selector(startSessionRolloverNetwork))
        )
        stack.addArrangedSubview(
            button(title: "Start slow URLSession request", id: "network-slow", action: #selector(startSlowNetwork))
        )
        stack.addArrangedSubview(
            button(title: "Start trace-only URLSession", id: "network-trace-only", action: #selector(startTraceOnlyNetwork))
        )
        stack.addArrangedSubview(
            button(title: "Use shared URLSession request", id: "network-shared", action: #selector(useSharedNetwork))
        )
        stack.addArrangedSubview(
            button(title: "Send RUM error", id: "error", action: #selector(sendError))
        )
        stack.addArrangedSubview(
            button(title: "Send correlated log", id: "log", action: #selector(sendLog))
        )
        stack.addArrangedSubview(
            button(title: "Start 3s trace span", id: "trace", action: #selector(startTrace))
        )
        stack.addArrangedSubview(
            button(title: "Start 3s feature operation", id: "operation", action: #selector(startOperation))
        )
        stack.addArrangedSubview(
            button(title: "Block main thread for 250ms", id: "long-task", action: #selector(makeLongTask))
        )

        for index in 1...20 {
            let filler = UILabel()
            filler.text = "Scroll marker \(index) — \(context.sceneLabel)"
            filler.textColor = .secondaryLabel
            filler.heightAnchor.constraint(equalToConstant: 30).isActive = true
            stack.addArrangedSubview(filler)
        }
    }

    private func button(title: String, id: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = title
        button.accessibilityIdentifier = "probe.\(context.sceneLabel).\(id)"
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func dismissModal() {
        dismiss(animated: true)
    }

    @objc private func openWindow() {
        mark("requested another window")
        RUMMultiSceneProbeState.requestNewScene(after: context)
    }

    @objc private func activateOtherWindow() {
        mark("requested other window activation")
        RUMMultiSceneProbeState.activateOtherScene(from: context)
    }

    @objc private func closeWindow() {
        mark("requested scene close")
        RUMMultiSceneProbeState.closeScene(for: view)
    }

    @objc private func pushDetail() {
        let nextDepth = screen.depth + 1
        mark("push detail \(nextDepth)")
        navigationController?.pushViewController(
            RUMMultiSceneProbeUIKitViewController(
                context: context,
                screen: .detail(depth: nextDepth)
            ),
            animated: true
        )
    }

    @objc private func pushSharedDetail() {
        mark("push shared detail")
        navigationController?.pushViewController(
            RUMMultiSceneProbeUIKitViewController(context: context, screen: .shared),
            animated: true
        )
    }

    @objc private func presentModal() {
        mark("present modal")
        let modal = RUMMultiSceneProbeUIKitViewController(context: context, screen: .modal)
        let navigation = UINavigationController(rootViewController: modal)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    @objc private func automaticTap() {
        mark("automatic tap handler")
    }

    @objc private func manualAction() {
        mark("manual action")
        RUMMonitor.shared().addAction(
            type: .custom,
            name: "manual-action-\(context.sceneLabel)",
            attributes: attributes(origin: "uikit-manual-action")
        )
    }

    @objc private func startResource() {
        let key = "resource-\(context.sceneLabel)-\(UUID().uuidString)"
        let url = URL(string: "https://multi-scene-probe.invalid/\(context.sceneLabel)/\(key)")!
        mark("resource started key=\(key)")
        RUMMonitor.shared().startResource(
            resourceKey: key,
            url: url,
            attributes: attributes(origin: "uikit-resource-start")
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
                    RUMMultiSceneProbeState.Attribute.origin: "uikit-resource-stop"
                ]
            )
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) resource finished key=\(key)"
            )
        }
    }

    @objc private func startSynchronousNetwork() {
        mark("URLSession synchronous")
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "uikit-sync"
        )
    }

    @objc private func startStructuredTaskNetwork() {
        mark("URLSession structured task scheduled within action window")
        Task { [context] in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-task-within-action-window"
            )
        }
    }

    @objc private func startExpiredStructuredTaskNetwork() {
        mark("URLSession structured task scheduled after action expiry")
        Task { [context] in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 200_000_000)
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-task-after-action-expiry"
            )
        }
    }

    @objc private func startSceneSwitchStructuredTaskNetwork() {
        mark("URLSession structured task scheduled in 3m for scene switch")
        Task { [context] in
            try? await Task.sleep(nanoseconds: 180_000_000_000)
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-task-scene-switch"
            )
        }
    }

    @objc private func startDetachedTaskNetwork() {
        mark("URLSession detached task scheduled in 3m")
        Task.detached { [context] in
            try? await Task.sleep(nanoseconds: 180_000_000_000)
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-task-detached"
            )
        }
    }

    @objc private func startGCDNetwork() {
        mark("URLSession GCD scheduled in 3m")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 180) { [context] in
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-gcd"
            )
        }
    }

    @objc private func startTimerNetwork() {
        mark("URLSession timer scheduled in 3m")
        Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [context] _ in
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-timer"
            )
        }
    }

    @objc private func startFilteredActionNetwork() {
        mark("URLSession filtered action")
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "uikit-filtered-action"
        )
    }

    @objc private func createNetworkTask() {
        RUMMultiSceneProbeState.prepareNetworkRequest(
            context: context,
            networkCase: "uikit-precreated-resumed-later"
        )
        mark("URLSession task created but not resumed")
    }

    @objc private func resumeNetworkTask() {
        guard RUMMultiSceneProbeState.resumePreparedNetworkRequest(context: context) else {
            mark("no pre-created URLSession task")
            return
        }
        mark("pre-created URLSession task resumed")
    }

    @objc private func startSessionRolloverNetwork() {
        mark("URLSession structured task scheduled across session rollover")
        Task { [context] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            RUMMultiSceneProbeState.startNetworkRequest(
                context: context,
                networkCase: "uikit-session-rollover-before-start"
            )
        }
        RUMMonitor.shared().stopSession()
        pushDetail()
    }

    @objc private func startSlowNetwork() {
        mark("slow URLSession started")
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "uikit-slow",
            delay: 5
        )
    }

    @objc private func startTraceOnlyNetwork() {
        mark("trace-only URLSession started")
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "uikit-trace-only",
            traceOnly: true
        )
    }

    @objc private func useSharedNetwork() {
        mark("shared URLSession requested")
        RUMMultiSceneProbeState.useSharedNetworkRequest(context: context)
    }

    @objc private func sendError() {
        mark("manual error")
        RUMMonitor.shared().addError(
            message: "probe-error-\(context.sceneLabel)",
            source: .source,
            attributes: attributes(origin: "uikit-error")
        )
    }

    @objc private func sendLog() {
        mark("correlated log")
        logger?.info(
            "probe-log-\(context.sceneLabel)",
            attributes: attributes(origin: "uikit-log")
        )
    }

    @objc private func startTrace() {
        mark("trace started")
        let span = Tracer.shared().startSpan(
            operationName: "probe-span-\(context.sceneLabel)"
        )
        span.setTag(key: RUMMultiSceneProbeState.Attribute.runID, value: context.runID)
        span.setTag(key: RUMMultiSceneProbeState.Attribute.sourceScene, value: context.sceneLabel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [context] in
            span.finish()
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) trace finished"
            )
        }
    }

    @objc private func startOperation() {
        let operationKey = UUID().uuidString
        mark("operation started key=\(operationKey)")
        RUMMonitor.shared().startOperation(
            name: "probe-operation",
            operationKey: operationKey,
            attributes: attributes(origin: "uikit-operation-start")
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [context] in
            RUMMonitor.shared().succeedOperation(
                name: "probe-operation",
                operationKey: operationKey,
                attributes: [
                    RUMMultiSceneProbeState.Attribute.runID: context.runID,
                    RUMMultiSceneProbeState.Attribute.sourceScene: context.sceneLabel,
                    RUMMultiSceneProbeState.Attribute.sceneSessionID: context.sceneSessionID,
                    RUMMultiSceneProbeState.Attribute.origin: "uikit-operation-stop"
                ]
            )
            RUMMultiSceneProbeState.record(
                "control source=\(context.sceneLabel) operation finished key=\(operationKey)"
            )
        }
    }

    @objc private func makeLongTask() {
        mark("long task started")
        Thread.sleep(forTimeInterval: 0.25)
        mark("long task finished")
    }

    private func attributes(origin: String) -> [String: Encodable] {
        var attributes = context.attributes
        attributes[RUMMultiSceneProbeState.Attribute.origin] = origin
        return attributes
    }

    private func mark(_ message: String) {
        statusLabel.text = message
        RUMMultiSceneProbeState.record(
            "control source=\(context.sceneLabel) screen=\(screen.pathComponent) \(message)"
        )
    }
}
