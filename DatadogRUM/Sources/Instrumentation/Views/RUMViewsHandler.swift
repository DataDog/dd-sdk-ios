/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import DatadogInternal

#if os(iOS)
/// Internal entry point for manual views that have an explicit scene owner.
/// Existing source-less monitor APIs retain their process-representative behavior.
internal protocol RUMSceneTargetedManualViewHandling: AnyObject {
    @MainActor
    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    )

    @MainActor
    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    )
}
#endif

// MARK: - RUMViewsHandler
internal final class RUMViewsHandler {
    /// RUM representation of a View.
    private struct View {
        /// The RUM View identity.
        let identity: ViewIdentifier

        /// View name used for RUM Explorer.
        let name: String

        /// View path used for RUM Explorer.
        let path: String

        /// Whether the view is modal, but untracked (should not send start / stop commands)
        let isUntrackedModal: Bool

        /// Custom attributes to attach to the View.
        let attributes: [AttributeKey: AttributeValue]

        /// The type of instrumentation that started this view.
        let instrumentationType: InstrumentationType
    }

    /// The current date provider.
    private let dateProvider: DateProvider

    #if !os(watchOS)
    /// `UIKit` view predicate. `nil` if `UIKit` auto-instrumentations is
    /// disabled.
    private let ddKitPredicate: DDKitRUMViewsPredicate?

    /// `SwiftUI` view predicate. `nil` if `SwiftUI` auto-instrumentations is
    /// disabled.
    private let swiftUIPredicate: SwiftUIRUMViewsPredicate?

    /// `SwiftUI` view name extractor.
    /// Extracts `SwiftUI` view name from view hierarchy.
    private let swiftUIViewNameExtractor: SwiftUIViewNameExtractor?
    #endif

    /// The notification center where this handler observes following `DDApplication` notifications:
    /// - `.didEnterBackgroundNotification`
    /// - `.willEnterForegroundNotification`
    private var notificationCenterProvider: NotificationCenterProvider?

    /// The RUM Command subscriber responsible for processing
    /// this publisher's commands.
    internal weak var subscriber: RUMCommandSubscriber?

    /// The appearing views stack.
    ///
    /// This stack allows to track appearing and disappearing views to consistently
    /// publish start and stop commands to the subscriber. The last item of the
    /// stack is the visible one, any items below it have appeared before but not yet
    /// disappeared. Therefore, they are considered not visible but can be revealed
    /// if the last item disappears.
    private var stack: [View] = []

    #if !os(watchOS)
    /// Creates a new `SwiftUI.View` handler to publish RUM view commands.
    /// - Parameters:
    ///   - dateProvider: The current date provider.
    ///   - predicate: `UIKit` view predicate. `nil`, if `UIKit`
    ///     auto-instrumentations is disabled.
    ///   - notificationCenter: The notification center where this handler
    ///    a set of `DDApplication` notifications.
    init(
        dateProvider: DateProvider,
        uiKitPredicate: DDKitRUMViewsPredicate?,
        swiftUIPredicate: SwiftUIRUMViewsPredicate?,
        swiftUIViewNameExtractor: SwiftUIViewNameExtractor?,
        notificationCenterProvider: NotificationCenterProvider
    ) {
        self.dateProvider = dateProvider
        self.ddKitPredicate = uiKitPredicate
        self.swiftUIPredicate = swiftUIPredicate
        self.swiftUIViewNameExtractor = swiftUIViewNameExtractor
        self.notificationCenterProvider = notificationCenterProvider

        #if os(macOS)
        notificationCenterProvider.workspaceCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: WorkspaceNotifications.willSleep,
            object: nil
        )
        notificationCenterProvider.workspaceCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: WorkspaceNotifications.didWake,
            object: nil
        )
        #else
        notificationCenterProvider.applicationCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenterProvider.applicationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
        #endif
    }

    #else
    /// Creates a new `SwiftUI.View` handler to publish RUM view commands on watchOS.
    /// - Parameters:
    ///   - dateProvider: The current date provider.
    ///   - notificationCenter: The notification center where this handler
    ///     observes app lifecycle notifications.
    init(dateProvider: DateProvider, notificationCenterProvider: NotificationCenterProvider) {
        self.dateProvider = dateProvider
        self.notificationCenterProvider = notificationCenterProvider

        notificationCenterProvider.applicationCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenterProvider.applicationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
    }
    #endif

    deinit {
    #if os(macOS)
        notificationCenterProvider?.workspaceCenter.removeObserver(
            self,
            name: WorkspaceNotifications.willSleep,
            object: nil
        )
        notificationCenterProvider?.workspaceCenter.removeObserver(
            self,
            name: WorkspaceNotifications.didWake,
            object: nil
        )
    #else
        notificationCenterProvider?.applicationCenter.removeObserver(
            self,
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenterProvider?.applicationCenter.removeObserver(
            self,
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
    #endif
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    private func add(view: View) {
        // Ignore the view if it's already visible
        if view.identity == stack.last?.identity {
            return
        }

        // Stop the last appearing view of the stack
        if let current = stack.last {
            stop(view: current)
        }

        if !view.isUntrackedModal {
            // Start the new appearing view
            start(view: view)
        }

        // Add/Move the appearing view to the top
        stack.removeAll(where: { $0.identity == view.identity })
        stack.append(view)
    }

    private func remove(identity: ViewIdentifier) {
        guard identity == stack.last?.identity else {
            // Remove any disappearing view from the stack if
            // it's not visible.
            return stack.removeAll(where: { $0.identity == identity })
        }

        // Stop and remove the visible view from the stack
        let view = stack.removeLast()
        stop(view: view)

        // Restart the previous view if any.
        if let current = stack.last {
            start(view: current)
        }
    }

    private func start(view: View) {
        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM view was started with \(view.instrumentationType) instrumentation, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before starting any views.
                """
            )
            return
        }

        guard !view.isUntrackedModal else {
            return
        }

        subscriber.process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: view.identity,
                name: view.name,
                path: view.path,
                globalAttributes: [:],
                attributes: view.attributes,
                instrumentationType: view.instrumentationType
            )
        )
    }

    private func stop(view: View) {
        guard !view.isUntrackedModal else {
            return
        }

        subscriber?.process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: view.attributes,
                identity: view.identity
            )
        )
    }

    /// Called when the application enters background state (iOS and similar platforms)
    /// or when the system enters sleep (macOS).
    @objc
    private func applicationDidEnterBackground() {
        if let current = stack.last {
            stop(view: current)
        }

        subscriber?.process(
            command: RUMHandleAppLifecycleEventCommand(
                time: dateProvider.now,
                event: .didEnterBackground
            )
        )
    }

    /// Called when the application enters foreground state (iOS and similar platforms)
    /// or when the system awakes from sleep (macOS).
    @objc
    private func applicationWillEnterForeground() {
        if let current = stack.last {
            start(view: current)
        }

        subscriber?.process(
            command: RUMHandleAppLifecycleEventCommand(
                time: dateProvider.now,
                event: .willEnterForeground
            )
        )
    }
}

// MARK: - NSViewControllerHandler
#if os(macOS)
extension RUMViewsHandler: NSViewControllerHandler {
    func notify_viewDidAppear(viewController: DDViewController) {
        guard (viewController is RUMDebuggingViewController) == false else {
            // Do not consider the RUM view scope debugger as a view that may be active.
            return
        }

        notify_viewDidAppear_impl(viewController: viewController, ddKitInstrumentationType: .appkit)
    }

    func notify_viewDidDisappear(viewController: DDViewController) {
        guard (viewController is RUMDebuggingViewController) == false else {
            // Do not consider the RUM view scope debugger as a view that may be active.
            return
        }

        remove(identity: ViewIdentifier(viewController))
    }
}
#endif

// MARK: - UIViewControllerHandler
#if !os(watchOS) && !os(macOS)
extension RUMViewsHandler: UIViewControllerHandler {
    func notify_viewDidAppear(viewController: DDViewController, animated: Bool) {
        notify_viewDidAppear_impl(viewController: viewController, ddKitInstrumentationType: .uikit)
    }

    func notify_viewDidDisappear(viewController: DDViewController, animated: Bool) {
        remove(identity: ViewIdentifier(viewController))
    }
}
#endif

// MARK: - ViewControllerHandler implementation
#if !os(watchOS)
extension RUMViewsHandler {
    func notify_viewDidAppear_impl(viewController: DDViewController, ddKitInstrumentationType: InstrumentationType) {
        let identity = ViewIdentifier(viewController)
        if let view = stack.first(where: { $0.identity == identity }) {
            // If the stack already contains the view controller, just restarts the view.
            // This prevents from calling the predicate when unnecessary.
            add(view: view)
        } else if let rumView = ddKitPredicate?.rumView(for: viewController) {
            add(
                view: .init(
                    identity: identity,
                    name: rumView.name,
                    path: rumView.path ?? viewController.canonicalClassName,
                    isUntrackedModal: rumView.isUntrackedModal,
                    attributes: rumView.attributes,
                    instrumentationType: ddKitInstrumentationType
                )
            )
        } else if let swiftUIPredicate,
                  let swiftUIViewNameExtractor,
                  let rumViewName = swiftUIViewNameExtractor.extractName(from: viewController),
                  let rumView = swiftUIPredicate.rumView(for: rumViewName) {
            // TODO: RUM-9888 - Ignore views already tracked manually with view modifiers
            add(
                view: .init(
                    identity: identity,
                    name: rumView.name,
                    path: rumView.path ?? viewController.canonicalClassName,
                    isUntrackedModal: rumView.isUntrackedModal,
                    attributes: rumView.attributes,
                    instrumentationType: .swiftuiAutomatic
                )
            )
        }
    }
}
#endif

// MARK: - SwiftUIViewHandler
extension RUMViewsHandler: SwiftUIViewHandler {
    /// Respond to a `SwiftUI.View.onAppear` event.
    ///
    /// - Parameters:
    ///   - key: The appearing `SwiftUI.View` key.
    ///   - name: The appearing `SwiftUI.View` name.
    ///   - attributes: The appearing `SwiftUI.View` attributes.
    func notify_onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue]) {
        add(
            view: .init(
                identity: ViewIdentifier(identity),
                name: name,
                path: path,
                isUntrackedModal: false,
                attributes: attributes,
                instrumentationType: .swiftui
            )
        )
    }

    /// Respond to a `SwiftUI.View.onDisappear` event.
    ///
    /// - Parameter key: The disappearing `SwiftUI.View` key.
    func notify_onDisappear(identity: String) {
        remove(identity: ViewIdentifier(identity))
    }
}

#if os(macOS)
internal protocol RUMViewsHandling: SwiftUIViewHandler, NSViewControllerHandler {
    var subscriber: RUMCommandSubscriber? { get }
}
#elseif os(watchOS)
internal protocol RUMViewsHandling: SwiftUIViewHandler {
    var subscriber: RUMCommandSubscriber? { get }
}
#else
internal protocol RUMViewsHandling: SwiftUIViewHandler, UIViewControllerHandler {
    var subscriber: RUMCommandSubscriber? { get }
}
#endif

extension RUMViewsHandler: RUMViewsHandling {}

#if os(iOS)
internal final class RUMSceneViewsHandler {
    /// UIKit location of a tracked controller inside a split-view hierarchy.
    /// This is navigation metadata only and is never serialized.
    internal struct UIKitSplitViewContext: Equatable {
        let splitViewController: ObjectIdentifier
        let column: Int
        let isStructural: Bool

        init(
            splitViewController: ObjectIdentifier,
            column: Int,
            isStructural: Bool = false
        ) {
            self.splitViewController = splitViewController
            self.column = column
            self.isStructural = isStructural
        }
    }

    /// A disappearing split-column view retained until UIKit either materializes
    /// its successor or completes the lifecycle turn without one.
    private struct PendingUIKitSplitViewRemoval {
        let token: UInt
        let identity: ViewIdentifier
        let sceneIdentifier: RUMSceneIdentifier
        let context: UIKitSplitViewContext
        let time: Date
    }

    /// RUM representation of a View.
    private struct View {
        /// The RUM View identity.
        let identity: ViewIdentifier

        /// View name used for RUM Explorer.
        let name: String

        /// View path used for RUM Explorer.
        let path: String

        /// Whether the view is modal, but untracked (should not send start / stop commands)
        let isUntrackedModal: Bool

        /// Custom attributes to attach to the View.
        let attributes: [AttributeKey: AttributeValue]

        /// The type of instrumentation that started this view.
        let instrumentationType: InstrumentationType

        /// Scene that owns this view. `nil` preserves the legacy process-wide stack.
        let sceneIdentifier: RUMSceneIdentifier?

        init(
            identity: ViewIdentifier,
            name: String,
            path: String,
            isUntrackedModal: Bool,
            attributes: [AttributeKey: AttributeValue],
            instrumentationType: InstrumentationType,
            sceneIdentifier: RUMSceneIdentifier?
        ) {
            self.identity = identity
            self.name = name
            self.path = path
            self.isUntrackedModal = isUntrackedModal
            self.attributes = attributes
            self.instrumentationType = instrumentationType
            self.sceneIdentifier = sceneIdentifier
        }
    }

    /// One navigation stack per scene. A `nil` scene is the legacy stack used
    /// when scene identity is unavailable.
    private struct ViewStack {
        let sceneIdentifier: RUMSceneIdentifier?
        var views: [View]
        var isActive: Bool
        /// View that was current when the first targeted manual view took
        /// authority. Its platform disappearance is ignored while it remains
        /// the immediate destination to reveal below the manual suffix.
        var retainedViewIdentityDuringManualAuthority: ViewIdentifier?
    }

    /// The current date provider.
    private let dateProvider: DateProvider

    /// `UIKit` view predicate. `nil` if `UIKit` auto-instrumentations is
    /// disabled.
    private let uiKitPredicate: UIKitRUMViewsPredicate?

    /// `SwiftUI` view predicate. `nil` if `SwiftUI` auto-instrumentations is
    /// disabled.
    private let swiftUIPredicate: SwiftUIRUMViewsPredicate?

    /// `SwiftUI` view name extractor.
    /// Extracts `SwiftUI` view name from view hierarchy.
    private let swiftUIViewNameExtractor: SwiftUIViewNameExtractor?

    /// Resolves the owning scene while the appeared view controller is still
    /// attached to its window. Injectable to keep scene routing deterministic in tests.
    private let sceneIdentifierProvider: (UIViewController) -> RUMSceneIdentifier?
    /// Resolves scene lifecycle notifications. Injectable for deterministic tests.
    private let sceneIdentifierFromNotification: (Notification) -> RUMSceneIdentifier?

    /// Enables iOS 27 split-column lifecycle reconciliation only for applications
    /// that explicitly declare multi-scene support.
    private let isMultiSceneApplication: Bool

    /// Defers a possible split-column removal until UIKit has delivered the
    /// corresponding appearance callback in the same lifecycle turn.
    private let scheduleUIKitSplitViewReconciliation: (@escaping () -> Void) -> Void

    /// Resolves UIKit containment separately from the reconciliation state
    /// machine so both can be tested deterministically.
    private let uiKitSplitViewContextProvider: (UIViewController) -> UIKitSplitViewContext?

    /// The notification center where this handler observes app lifecycle notifications:
    /// - `.didEnterBackground`
    /// - `.willEnterForeground`
    private let notificationCenterProvider: NotificationCenterProvider

    /// The RUM Command subscriber responsible for processing
    /// this publisher's commands.
    internal weak var subscriber: RUMCommandSubscriber?

    /// The appearing views stacks, independently keyed by scene.
    ///
    /// This stack allows to track appearing and disappearing views to consistently
    /// publish start and stop commands to the subscriber. The last item of the
    /// stack is the visible one, any items below it have appeared before but not yet
    /// disappeared. Therefore, they are considered not visible but can be revealed
    /// if the last item disappears.
    private var stacks: [ViewStack] = []

    /// Process lifecycle fallback for views whose scene is unavailable, and
    /// for a scene whose lifecycle notification has not arrived yet.
    private var isApplicationActive = true

    /// Last lifecycle state observed for each scene, including scenes that do
    /// not have a tracked view stack yet. Scene notifications can precede
    /// `viewDidAppear`, especially while creating or restoring a window.
    private var sceneActivityByIdentifier: [RUMSceneIdentifier: Bool] = [:]

    /// Once scene lifecycle has been observed, only known live scenes may
    /// publish. This avoids retaining every disconnected session identifier.

    /// Read once on the main thread, then released. Captures value-only state
    /// for scenes that connected before the handler was initialized.
    private var initialSceneActivityProvider: (() -> [RUMSceneIdentifier: Bool])?

    /// Split metadata captured while each UIKit controller is attached.
    private var uiKitSplitViewContexts: [(identity: ViewIdentifier, context: UIKitSplitViewContext)] = []

    /// At most one active disappearance can be pending for a scene because each
    /// scene has one visible RUM stack entry.
    private var pendingUIKitSplitViewRemovals: [PendingUIKitSplitViewRemoval] = []
    private var nextPendingUIKitSplitViewRemovalToken: UInt = 0

    /// Creates a new `SwiftUI.View` handler to publish RUM view commands.
    /// - Parameters:
    ///   - dateProvider: The current date provider.
    ///   - predicate: `UIKit` view predicate. `nil`, if `UIKit`
    ///     auto-instrumentations is disabled.
    ///   - notificationCenter: The notification center where this handler
    ///    a set of `UIApplication` notifications.
    init(
        dateProvider: DateProvider,
        uiKitPredicate: UIKitRUMViewsPredicate?,
        swiftUIPredicate: SwiftUIRUMViewsPredicate?,
        swiftUIViewNameExtractor: SwiftUIViewNameExtractor?,
        notificationCenterProvider: NotificationCenterProvider,
        isMultiSceneApplication: Bool = false,
        sceneIdentifierProvider: @escaping (UIViewController) -> RUMSceneIdentifier? = { viewController in
            guard let identifier = viewController.viewIfLoaded?
                .window?
                .windowScene?
                .session
                .persistentIdentifier else {
                return nil
            }
            return RUMSceneIdentifier(rawValue: identifier)
        },
        sceneIdentifierFromNotification: @escaping (Notification) -> RUMSceneIdentifier? = { notification in
            guard let scene = notification.object as? UIScene else {
                return nil
            }
            return RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)
        },
        initialSceneActivityProvider: @escaping () -> [RUMSceneIdentifier: Bool] = {
            var activity: [RUMSceneIdentifier: Bool] = [:]
            for scene in UIApplication.dd.managedShared?.connectedScenes ?? []
                where scene.activationState != .unattached {
                activity[RUMSceneIdentifier(rawValue: scene.session.persistentIdentifier)] =
                    scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
            }
            return activity
        },
        uiKitSplitViewContextProvider: ((UIViewController) -> UIKitSplitViewContext?)? = nil,
        scheduleUIKitSplitViewReconciliation: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.dateProvider = dateProvider
        self.uiKitPredicate = uiKitPredicate
        self.swiftUIPredicate = swiftUIPredicate
        self.swiftUIViewNameExtractor = swiftUIViewNameExtractor
        self.sceneIdentifierProvider = sceneIdentifierProvider
        self.sceneIdentifierFromNotification = sceneIdentifierFromNotification
        self.initialSceneActivityProvider = initialSceneActivityProvider
        self.isMultiSceneApplication = isMultiSceneApplication
        self.scheduleUIKitSplitViewReconciliation = scheduleUIKitSplitViewReconciliation
        self.uiKitSplitViewContextProvider = uiKitSplitViewContextProvider
            ?? Self.resolveUIKitSplitViewContext
        self.notificationCenterProvider = notificationCenterProvider
        let notificationCenter = notificationCenterProvider.applicationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sceneWillConnect(_:)),
            name: UIScene.willConnectNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sceneDidEnterBackground(_:)),
            name: UIScene.didEnterBackgroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sceneWillEnterForeground(_:)),
            name: UIScene.willEnterForegroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sceneDidDisconnect(_:)),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
        // Scene inventory is seeded once by the first main-thread callback.
    }

    deinit {
        notificationCenterProvider.applicationCenter.removeObserver(
            self,
            name: ApplicationNotifications.didEnterBackground,
            object: nil
        )
        notificationCenterProvider.applicationCenter.removeObserver(
            self,
            name: ApplicationNotifications.willEnterForeground,
            object: nil
        )
        notificationCenterProvider.applicationCenter.removeObserver(self, name: UIScene.willConnectNotification, object: nil)
        notificationCenterProvider.applicationCenter.removeObserver(self, name: UIScene.didEnterBackgroundNotification, object: nil)
        notificationCenterProvider.applicationCenter.removeObserver(self, name: UIScene.willEnterForegroundNotification, object: nil)
        notificationCenterProvider.applicationCenter.removeObserver(self, name: UIScene.didDisconnectNotification, object: nil)
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    @discardableResult
    private func add(view: View, stoppingCurrentAt time: Date? = nil) -> Bool {
        if let sceneIdentifier = view.sceneIdentifier {
            guard canTrackViews(in: sceneIdentifier) else {
                return false
            }
            if sceneActivityByIdentifier[sceneIdentifier] == nil {
                sceneActivityByIdentifier[sceneIdentifier] = isApplicationActive
            }
        }

        let stackIndex: Int
        if let existingIndex = stacks.firstIndex(where: { $0.sceneIdentifier == view.sceneIdentifier }) {
            stackIndex = existingIndex
        } else {
            let isActive = view.sceneIdentifier
                .flatMap { sceneActivityByIdentifier[$0] }
                ?? isApplicationActive
            stacks.append(
                ViewStack(
                    sceneIdentifier: view.sceneIdentifier,
                    views: [],
                    isActive: isActive,
                    retainedViewIdentityDuringManualAuthority: nil
                )
            )
            stackIndex = stacks.endIndex - 1
        }

        var stack = stacks[stackIndex].views
        let isActive = stacks[stackIndex].isActive

        if let insertionIndex = insertionIndexBelowManualAuthority(
            for: view,
            in: stack
        ) {
            if insertionIndex > stack.startIndex,
               stack[stack.index(before: insertionIndex)].identity == view.identity {
                return true
            }

            stack.removeAll { candidate in
                candidate.instrumentationType != .manual
                    && candidate.identity == view.identity
            }
            let updatedInsertionIndex = firstIndexOfManualSuffix(in: stack) ?? stack.endIndex
            stack.insert(view, at: updatedInsertionIndex)
            stacks[stackIndex].views = stack
            return true
        }

        // Ignore the view if it's already visible
        if view.identity == stack.last?.identity {
            return true
        }

        if view.instrumentationType == .manual,
           !stack.contains(where: { $0.instrumentationType == .manual }) {
            stacks[stackIndex].retainedViewIdentityDuringManualAuthority = stack.last?.identity
        }

        // Stop the last appearing view of the stack
        if isActive, let current = stack.last {
            stop(view: current, time: time)
        }

        if isActive && !view.isUntrackedModal {
            // Start the new appearing view
            start(view: view)
        }

        // Add/Move the appearing view to the top
        stack.removeAll(where: { $0.identity == view.identity })
        stack.append(view)
        stacks[stackIndex].views = stack
        return true
    }

    /// Returns where a lower-priority platform view should be staged while an
    /// explicitly targeted manual view remains authoritative in this scene.
    private func insertionIndexBelowManualAuthority(
        for view: View,
        in stack: [View]
    ) -> Int? {
        guard view.instrumentationType.priority < InstrumentationType.manual.priority else {
            return nil
        }
        return firstIndexOfManualSuffix(in: stack)
    }

    private func firstIndexOfManualSuffix(in stack: [View]) -> Int? {
        guard stack.last?.instrumentationType == .manual else {
            return nil
        }

        var index = stack.endIndex
        while index > stack.startIndex,
              stack[stack.index(before: index)].instrumentationType == .manual {
            index = stack.index(before: index)
        }
        return index
    }

    private func remove(
        identity: ViewIdentifier,
        sceneIdentifier: RUMSceneIdentifier? = nil,
        time: Date? = nil,
        stopAttributes: [AttributeKey: AttributeValue]? = nil,
        removeRetainedPlatformView: Bool = false
    ) {
        discardPendingUIKitSplitViewRemoval(identity: identity, sceneIdentifier: sceneIdentifier)
        guard let stackIndex = stacks.firstIndex(where: { stack in
            let matchesScene = stack.sceneIdentifier == sceneIdentifier
            return matchesScene && stack.views.contains(where: { $0.identity == identity })
        }) else {
            return
        }

        var stack = stacks[stackIndex].views
        let isActive = stacks[stackIndex].isActive

        if removeRetainedPlatformView,
           stacks[stackIndex].retainedViewIdentityDuringManualAuthority == identity {
            stacks[stackIndex].retainedViewIdentityDuringManualAuthority = nil
        }

        if !removeRetainedPlatformView,
           let manualSuffixIndex = firstIndexOfManualSuffix(in: stack),
           manualSuffixIndex > stack.startIndex,
           stacks[stackIndex].retainedViewIdentityDuringManualAuthority == identity,
           stack[stack.index(before: manualSuffixIndex)].identity == identity {
            return
        }

        guard identity == stack.last?.identity else {
            // Remove any disappearing view from the stack if
            // it's not visible.
            stack.removeAll(where: { $0.identity == identity })
            if stack.isEmpty {
                stacks.remove(at: stackIndex)
            } else {
                if !stack.contains(where: { $0.instrumentationType == .manual }) {
                    stacks[stackIndex].retainedViewIdentityDuringManualAuthority = nil
                }
                stacks[stackIndex].views = stack
            }
            discardUIKitSplitViewContextIfUntracked(identity: identity)
            return
        }

        // Stop and remove the visible view from the stack
        let view = stack.removeLast()
        if isActive {
            stop(view: view, time: time, attributes: stopAttributes)
        }

        if !stack.contains(where: { $0.instrumentationType == .manual }) {
            stacks[stackIndex].retainedViewIdentityDuringManualAuthority = nil
        }

        // Restart the previous view if any.
        if isActive, let current = stack.last {
            start(view: current, time: time)
        }

        if stack.isEmpty {
            stacks.remove(at: stackIndex)
        } else {
            stacks[stackIndex].views = stack
        }

        discardUIKitSplitViewContextIfUntracked(identity: identity)
    }

    /// Replaces an existing tracked occurrence in place. Unlike `remove`,
    /// this does not restart the view below the replaced slot before starting
    /// the new occurrence.
    @discardableResult
    private func replace(identity: ViewIdentifier, with view: View) -> Bool {
        guard let stackIndex = stacks.firstIndex(where: { stack in
            stack.sceneIdentifier == view.sceneIdentifier
                && stack.views.contains(where: { $0.identity == identity })
        }) else {
            return false
        }

        var stack = stacks[stackIndex].views
        guard let viewIndex = stack.firstIndex(where: { $0.identity == identity }) else {
            return false
        }

        let isActiveOccurrence = stacks[stackIndex].isActive
            && viewIndex == stack.index(before: stack.endIndex)
        let oldView = stack[viewIndex]
        if isActiveOccurrence {
            stop(view: oldView)
        }

        stack[viewIndex] = view
        stacks[stackIndex].views = stack

        if isActiveOccurrence {
            start(view: view)
        }
        return true
    }

    private func start(view: View, time: Date? = nil) {
        guard let subscriber = subscriber else {
            DD.logger.warn(
                """
                A RUM view was started with \(view.instrumentationType) instrumentation, but RUM tracking appears to be disabled.
                Ensure `RUM.enable()` is called before starting any views.
                """
            )
            return
        }

        guard !view.isUntrackedModal else {
            return
        }

        subscriber.process(
            command: RUMStartViewCommand(
                time: time ?? dateProvider.now,
                identity: view.identity,
                name: view.name,
                path: view.path,
                globalAttributes: [:],
                attributes: view.attributes,
                instrumentationType: view.instrumentationType,
                target: target(for: view)
            )
        )
    }

    private func stop(
        view: View,
        time: Date? = nil,
        attributes: [AttributeKey: AttributeValue]? = nil
    ) {
        guard !view.isUntrackedModal else {
            return
        }

        var command = RUMStopViewCommand(
                time: time ?? dateProvider.now,
                attributes: attributes ?? view.attributes,
                identity: view.identity
        )
        command.target = target(for: view)
        subscriber?.process(command: command)
    }

    private func target(for view: View) -> RUMCommandTarget {
        view.sceneIdentifier.map(RUMCommandTarget.scene) ?? .processRepresentative
    }

    private func captureUIKitSplitViewContext(
        for viewController: UIViewController,
        identity: ViewIdentifier
    ) {
        guard isMultiSceneApplication else {
            return
        }

        let context = uiKitSplitViewContextProvider(viewController)

        uiKitSplitViewContexts.removeAll { $0.identity == identity }
        if let context {
            uiKitSplitViewContexts.append((identity: identity, context: context))
        }
    }

    private static func resolveUIKitSplitViewContext(
        for viewController: UIViewController
    ) -> UIKitSplitViewContext? {
        guard #available(iOS 27.0, *) else {
            return nil
        }
        guard let splitViewController = viewController.splitViewController else {
            return nil
        }

        let columns: [UISplitViewController.Column] = [
            .primary,
            .supplementary,
            .secondary,
            .compact,
            .inspector,
        ]
        guard let column = columns.first(where: { column in
            guard let root = splitViewController.viewController(for: column) else {
                return false
            }
            return Self.belongsToSplitColumn(viewController, rootedAt: root)
        }) else {
            return nil
        }

        return UIKitSplitViewContext(
            splitViewController: ObjectIdentifier(splitViewController),
            column: column.rawValue,
            isStructural: Self.isStructuralUIKitSplitColumn(
                column,
                in: splitViewController
            )
        )
    }

    private static func isStructuralUIKitSplitColumn(
        _ column: UISplitViewController.Column,
        in splitViewController: UISplitViewController
    ) -> Bool {
        guard
            column == .primary || column == .supplementary,
            splitViewController.traitCollection.horizontalSizeClass == .regular
        else {
            return false
        }

        switch splitViewController.displayMode {
        case .oneBesideSecondary,
             .oneOverSecondary,
             .twoBesideSecondary,
             .twoOverSecondary,
             .twoDisplaceSecondary:
            return true
        case .automatic, .secondaryOnly:
            return false
        @unknown default:
            return false
        }
    }

    private static func belongsToSplitColumn(
        _ viewController: UIViewController,
        rootedAt root: UIViewController
    ) -> Bool {
        var ancestor: UIViewController? = viewController
        while let current = ancestor {
            if current === root {
                return true
            }
            ancestor = current.parent
        }

        guard let navigationController = viewController.navigationController else {
            return false
        }
        return navigationController === root || navigationController === root.navigationController
    }

    private func uiKitSplitViewContext(for identity: ViewIdentifier) -> UIKitSplitViewContext? {
        uiKitSplitViewContexts.first(where: { $0.identity == identity })?.context
    }

    private func discardUIKitSplitViewContextIfUntracked(identity: ViewIdentifier) {
        guard !stacks.contains(where: { stack in
            stack.views.contains(where: { $0.identity == identity })
        }) else {
            return
        }
        uiKitSplitViewContexts.removeAll { $0.identity == identity }
    }

    /// Returns `true` when the ordinary removal must wait for a possible
    /// materialized successor in the same split column.
    private func deferUIKitSplitViewRemovalIfNeeded(identity: ViewIdentifier) -> Bool {
        guard isMultiSceneApplication, #available(iOS 27.0, *) else {
            return false
        }
        guard let stack = stacks.first(where: { $0.views.last?.identity == identity }),
              let sceneIdentifier = stack.sceneIdentifier,
              let outgoing = stack.views.last,
              outgoing.instrumentationType == .uikit,
              !outgoing.isUntrackedModal,
              let outgoingContext = uiKitSplitViewContext(for: identity) else {
            return false
        }
        if let pending = pendingUIKitSplitViewRemovals.first(where: {
            $0.sceneIdentifier == sceneIdentifier
        }) {
            return pending.identity == identity
        }

        nextPendingUIKitSplitViewRemovalToken &+= 1
        let pending = PendingUIKitSplitViewRemoval(
            token: nextPendingUIKitSplitViewRemovalToken,
            identity: identity,
            sceneIdentifier: sceneIdentifier,
            context: outgoingContext,
            time: dateProvider.now
        )
        pendingUIKitSplitViewRemovals.append(pending)
        scheduleUIKitSplitViewReconciliation { [weak self] in
            self?.flushPendingUIKitSplitViewRemoval(token: pending.token)
        }
        return true
    }

    /// Consumes an old-first UIKit callback pair without exposing a sibling
    /// split column between the two real navigation occurrences.
    private func consumePendingUIKitSplitViewRemoval(with view: View) -> Bool {
        guard view.instrumentationType == .uikit,
              let sceneIdentifier = view.sceneIdentifier,
              let pendingIndex = pendingUIKitSplitViewRemovals.firstIndex(where: {
                  $0.sceneIdentifier == sceneIdentifier
              }) else {
            return false
        }

        let pending = pendingUIKitSplitViewRemovals[pendingIndex]
        if pending.identity == view.identity {
            // UIKit reverted a lifecycle transition before a new path item was
            // materialized. Keep the existing RUM occurrence active.
            pendingUIKitSplitViewRemovals.remove(at: pendingIndex)
            return true
        }

        guard !view.isUntrackedModal,
              let incomingContext = uiKitSplitViewContext(for: view.identity),
              incomingContext == pending.context else {
            // Preserve ordinary handling for an unrelated appearance, but
            // remove the now-covered outgoing item immediately. Leaving it
            // pending could let another same-turn disappearance reveal it again.
            pendingUIKitSplitViewRemovals.remove(at: pendingIndex)
            add(view: view, stoppingCurrentAt: pending.time)
            remove(
                identity: pending.identity,
                sceneIdentifier: pending.sceneIdentifier,
                time: pending.time
            )
            return true
        }

        pendingUIKitSplitViewRemovals.remove(at: pendingIndex)
        guard transitionActiveUIKitView(
            from: pending.identity,
            to: view,
            stoppedAt: pending.time
        ) else {
            remove(
                identity: pending.identity,
                sceneIdentifier: pending.sceneIdentifier,
                time: pending.time
            )
            return false
        }
        return true
    }

    private func transitionActiveUIKitView(
        from oldIdentity: ViewIdentifier,
        to view: View,
        stoppedAt: Date
    ) -> Bool {
        guard let stackIndex = stacks.firstIndex(where: { stack in
            stack.sceneIdentifier == view.sceneIdentifier
                && stack.views.last?.identity == oldIdentity
        }) else {
            return false
        }

        var stack = stacks[stackIndex].views
        let oldView = stack.removeLast()
        let isActive = stacks[stackIndex].isActive
        if isActive {
            stop(view: oldView, time: stoppedAt)
        }

        // A pop can return the exact same platform controller that represented
        // an earlier path item. Remove that stored item but always start the
        // incoming one as a fresh RUM occurrence.
        stack.removeAll { $0.identity == view.identity }
        stack.append(view)
        stacks[stackIndex].views = stack
        discardUIKitSplitViewContextIfUntracked(identity: oldIdentity)

        if isActive {
            start(view: view)
        }
        return true
    }

    private func flushPendingUIKitSplitViewRemoval(token: UInt) {
        guard Thread.isMainThread else {
            return
        }
        guard let index = pendingUIKitSplitViewRemovals.firstIndex(where: { $0.token == token }) else {
            return
        }
        let pending = pendingUIKitSplitViewRemovals.remove(at: index)
        remove(
            identity: pending.identity,
            sceneIdentifier: pending.sceneIdentifier,
            time: pending.time
        )
    }

    private func flushPendingUIKitSplitViewRemovals(sceneIdentifier: RUMSceneIdentifier? = nil) {
        let tokens = pendingUIKitSplitViewRemovals.compactMap { pending in
            sceneIdentifier == nil || pending.sceneIdentifier == sceneIdentifier ? pending.token : nil
        }
        for token in tokens {
            flushPendingUIKitSplitViewRemoval(token: token)
        }
    }

    private func discardPendingUIKitSplitViewRemoval(
        identity: ViewIdentifier,
        sceneIdentifier: RUMSceneIdentifier?
    ) {
        pendingUIKitSplitViewRemovals.removeAll { pending in
            pending.identity == identity
                && pending.sceneIdentifier == sceneIdentifier
        }
    }

    private func pendingUIKitSplitViewRemovalTime(for stack: ViewStack) -> Date? {
        guard let sceneIdentifier = stack.sceneIdentifier,
              let identity = stack.views.last?.identity else {
            return nil
        }
        return pendingUIKitSplitViewRemovals.first(where: { pending in
            pending.sceneIdentifier == sceneIdentifier && pending.identity == identity
        })?.time
    }

    private func suspendStack(at index: Int, time: Date? = nil) {
        guard stacks[index].isActive else {
            return
        }
        if let current = stacks[index].views.last {
            stop(view: current, time: time)
        }
        stacks[index].isActive = false
    }

    private func resumeStack(at index: Int) {
        guard !stacks[index].isActive else {
            return
        }
        stacks[index].isActive = true
        if let current = stacks[index].views.last {
            start(view: current)
        }
    }

    @objc
    private func applicationDidEnterBackground() {
        guard Thread.isMainThread else {
            return
        }
        isApplicationActive = false
        seedInitialSceneActivity()
        for sceneIdentifier in Array(sceneActivityByIdentifier.keys) {
            sceneActivityByIdentifier[sceneIdentifier] = false
        }
        for index in stacks.indices {
            let pendingRemovalTime = pendingUIKitSplitViewRemovalTime(for: stacks[index])
            if let sceneIdentifier = stacks[index].sceneIdentifier {
                sceneActivityByIdentifier[sceneIdentifier] = false
            }
            suspendStack(at: index, time: pendingRemovalTime)
        }
        // Remove pending outgoing views only after every stack is inactive so
        // backgrounding cannot manufacture a sibling occurrence.
        flushPendingUIKitSplitViewRemovals()

        subscriber?.process(
            command: RUMHandleAppLifecycleEventCommand(
                time: dateProvider.now,
                event: .didEnterBackground
            )
        )
    }

    @objc
    private func applicationWillEnterForeground() {
        guard Thread.isMainThread else {
            return
        }
        isApplicationActive = true
        // Scene-backed stacks resume from their own UIScene notification. The
        // application notification remains the fallback for the legacy stack.
        for index in stacks.indices where stacks[index].sceneIdentifier == nil {
            resumeStack(at: index)
        }

        subscriber?.process(
            command: RUMHandleAppLifecycleEventCommand(
                time: dateProvider.now,
                event: .willEnterForeground
            )
        )
    }

    private func seedInitialSceneActivity() {
        guard Thread.isMainThread, let provider = initialSceneActivityProvider else {
            return
        }
        initialSceneActivityProvider = nil
        sceneActivityByIdentifier.merge(provider()) { observed, _ in observed }
    }

    /// Only an initially connected scene or a subsequent connection may publish.
    func canTrackViews(in sceneIdentifier: RUMSceneIdentifier) -> Bool {
        guard Thread.isMainThread else {
            return false
        }
        seedInitialSceneActivity()
        return sceneActivityByIdentifier[sceneIdentifier] != nil
    }

    @objc
    private func sceneWillConnect(_ notification: Notification) {
        guard Thread.isMainThread else {
            return
        }
        guard let sceneIdentifier = sceneIdentifierFromNotification(notification) else {
            return
        }
        seedInitialSceneActivity()
        sceneActivityByIdentifier[sceneIdentifier] = false
    }

    @objc
    private func sceneDidEnterBackground(_ notification: Notification) {
        guard Thread.isMainThread else {
            return
        }
        guard let sceneIdentifier = sceneIdentifierFromNotification(notification) else {
            return
        }
        guard canTrackViews(in: sceneIdentifier) else {
            return
        }
        sceneActivityByIdentifier[sceneIdentifier] = false
        guard let index = stacks.firstIndex(where: { $0.sceneIdentifier == sceneIdentifier }) else {
            flushPendingUIKitSplitViewRemovals(sceneIdentifier: sceneIdentifier)
            return
        }
        let pendingRemovalTime = pendingUIKitSplitViewRemovalTime(for: stacks[index])
        suspendStack(at: index, time: pendingRemovalTime)
        flushPendingUIKitSplitViewRemovals(sceneIdentifier: sceneIdentifier)
    }

    @objc
    private func sceneWillEnterForeground(_ notification: Notification) {
        guard Thread.isMainThread else {
            return
        }
        guard let sceneIdentifier = sceneIdentifierFromNotification(notification) else {
            return
        }
        guard canTrackViews(in: sceneIdentifier) else {
            return
        }
        sceneActivityByIdentifier[sceneIdentifier] = true
        guard let index = stacks.firstIndex(where: { $0.sceneIdentifier == sceneIdentifier }) else {
            return
        }
        resumeStack(at: index)
    }

    @objc
    private func sceneDidDisconnect(_ notification: Notification) {
        guard Thread.isMainThread else {
            return
        }
        guard let sceneIdentifier = sceneIdentifierFromNotification(notification) else {
            return
        }
        seedInitialSceneActivity()
        sceneActivityByIdentifier.removeValue(forKey: sceneIdentifier)
        guard let index = stacks.firstIndex(where: { $0.sceneIdentifier == sceneIdentifier }) else {
            pendingUIKitSplitViewRemovals.removeAll { $0.sceneIdentifier == sceneIdentifier }
            return
        }
        let pendingRemovalTime = pendingUIKitSplitViewRemovalTime(for: stacks[index])
        pendingUIKitSplitViewRemovals.removeAll { $0.sceneIdentifier == sceneIdentifier }
        let disconnectedIdentities = stacks[index].views.map(\.identity)
        suspendStack(at: index, time: pendingRemovalTime)
        stacks.remove(at: index)
        for identity in disconnectedIdentities {
            discardUIKitSplitViewContextIfUntracked(identity: identity)
        }
    }
}

// MARK: - UIViewControllerHandler
extension RUMSceneViewsHandler: UIViewControllerHandler {
    func notify_viewDidAppear(viewController: UIViewController, animated: Bool) {
        guard Thread.isMainThread else {
            return
        }
        let identity = ViewIdentifier(viewController)
        let attachedSceneIdentifier = sceneIdentifierProvider(viewController)
        if let attachedSceneIdentifier, !canTrackViews(in: attachedSceneIdentifier) {
            return
        }
        if isMultiSceneApplication,
            #available(iOS 27.0, *),
            uiKitSplitViewContextProvider(viewController)?.isStructural == true {
            // In a regular-width split hierarchy, primary and supplementary
            // columns are structural navigation context. The scene's semantic
            // RUM destination is the independently visible detail column.
            return
        }
        if let view = stacks.lazy.flatMap(\ViewStack.views).first(where: { $0.identity == identity }) {
            // If the stack already contains the view controller, just restarts the view.
            // This prevents from calling the predicate when unnecessary.
            if view.instrumentationType == .uikit {
                captureUIKitSplitViewContext(for: viewController, identity: identity)
            }
            let currentSceneIdentifier = attachedSceneIdentifier ?? view.sceneIdentifier
            if currentSceneIdentifier == view.sceneIdentifier {
                if consumePendingUIKitSplitViewRemoval(with: view) {
                    return
                }
                add(view: view)
            } else {
                remove(
                    identity: identity,
                    sceneIdentifier: view.sceneIdentifier,
                    removeRetainedPlatformView: true
                )
                captureUIKitSplitViewContext(for: viewController, identity: identity)
                add(
                    view: .init(
                        identity: view.identity,
                        name: view.name,
                        path: view.path,
                        isUntrackedModal: view.isUntrackedModal,
                        attributes: view.attributes,
                        instrumentationType: view.instrumentationType,
                        sceneIdentifier: currentSceneIdentifier
                    )
                )
            }
        } else if let rumView = uiKitPredicate?.rumView(for: viewController) {
            captureUIKitSplitViewContext(for: viewController, identity: identity)
            let view = View(
                identity: identity,
                name: rumView.name,
                path: rumView.path ?? viewController.canonicalClassName,
                isUntrackedModal: rumView.isUntrackedModal,
                attributes: rumView.attributes,
                instrumentationType: .uikit,
                sceneIdentifier: attachedSceneIdentifier
            )
            if consumePendingUIKitSplitViewRemoval(with: view) {
                return
            }
            add(view: view)
        } else if let swiftUIPredicate,
                  let swiftUIViewNameExtractor,
                  let rumViewName = swiftUIViewNameExtractor.extractName(from: viewController),
                  let rumView = swiftUIPredicate.rumView(for: rumViewName) {
            add(
                view: .init(
                    identity: identity,
                    name: rumView.name,
                    path: rumView.path ?? viewController.canonicalClassName,
                    isUntrackedModal: rumView.isUntrackedModal,
                    attributes: rumView.attributes,
                    instrumentationType: .swiftuiAutomatic,
                    sceneIdentifier: attachedSceneIdentifier
                )
            )
        }
    }

    func notify_viewDidDisappear(viewController: UIViewController, animated: Bool) {
        guard Thread.isMainThread else {
            return
        }
        let identity = ViewIdentifier(viewController)
        if deferUIKitSplitViewRemovalIfNeeded(identity: identity) {
            return
        }
        guard let owner = stacks.first(where: { $0.views.contains(where: { $0.identity == identity }) }) else {
            return
        }
        remove(identity: identity, sceneIdentifier: owner.sceneIdentifier)
    }
}

// MARK: - SwiftUIViewHandler
extension RUMSceneViewsHandler: SwiftUIViewHandler {
    func notify_onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue]) {
        guard Thread.isMainThread else {
            return
        }
        add(view: .init(
            identity: ViewIdentifier(identity),
            name: name,
            path: path,
            isUntrackedModal: false,
            attributes: attributes,
            instrumentationType: .swiftui,
            sceneIdentifier: nil
        ))
    }

    func notify_onDisappear(identity: String) {
        guard Thread.isMainThread else {
            return
        }
        remove(identity: ViewIdentifier(identity), sceneIdentifier: nil)
    }
}

extension RUMSceneViewsHandler: RUMSceneTargetedManualViewHandling {
    @MainActor
    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        add(
            view: .init(
                identity: ViewIdentifier(key),
                name: name ?? key,
                path: key,
                isUntrackedModal: false,
                attributes: attributes,
                instrumentationType: .manual,
                sceneIdentifier: sceneIdentifier
            )
        )
    }

    @MainActor
    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        remove(
            identity: ViewIdentifier(key),
            sceneIdentifier: sceneIdentifier,
            stopAttributes: attributes
        )
    }
}

extension RUMSceneViewsHandler: RUMViewsHandling {}
#endif
