/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import OSLog
import DatadogCore
import DatadogLogs
import DatadogRUM
import DatadogSessionReplay
import DatadogTrace

final class RUMMultiSceneProbeScenario: TestScenario {
    static let storyboardName = ""

    func override(configuration: inout Datadog.Configuration) {
        guard Environment.isRunningInteractive() else {
            return
        }

        configuration.clientToken = Environment.readClientToken()
        configuration.env = "multi-scene-probe"
        configuration.service = RUMMultiSceneProbeState.serviceName
        configuration.batchSize = .small
        configuration.uploadFrequency = .frequent
    }

    func configureFeatures() {
        let applicationID = Environment.isRunningInteractive()
            ? Environment.readRUMApplicationID()
            : "rum-multi-scene-probe-application-id"

        let rumConfiguration = RUM.Configuration(
            applicationID: applicationID,
            uiKitViewsPredicate: RUMMultiSceneProbeUIKitViewsPredicate(),
            uiKitActionsPredicate: RUMMultiSceneProbeUIKitActionsPredicate(),
            swiftUIViewsPredicate: nil,
            swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: false),
            urlSessionTracking: .init(
                firstPartyHostsTracing: .traceWithHeaders(
                    hostsWithHeaders: ["multi-scene-probe.invalid": [.datadog, .tracecontext]],
                    sampleRate: 100
                ),
                resourceAttributesProvider: { request, _, _, _ in
                    RUMMultiSceneProbeState.networkAttributes(from: request)
                },
                disallowList: ["https://multi-scene-probe.invalid/trace-only*"]
            ),
            trackBackgroundEvents: true,
            longTaskThreshold: 0.1,
            viewEventMapper: { event in
                RUMMultiSceneProbeState.record(viewEvent: event)
                return event
            },
            resourceEventMapper: { event in
                RUMMultiSceneProbeState.record(resourceEvent: event)
                return event
            },
            actionEventMapper: { event in
                RUMMultiSceneProbeState.record(actionEvent: event)
                return event
            },
            errorEventMapper: { event in
                RUMMultiSceneProbeState.record(errorEvent: event)
                return event
            },
            longTaskEventMapper: { event in
                RUMMultiSceneProbeState.record(longTaskEvent: event)
                return event
            },
            onSessionStart: { sessionID, isDiscarded in
                RUMMultiSceneProbeState.record(
                    "session id=\(sessionID) discarded=\(isDiscarded)"
                )
            },
            customEndpoint: Environment.serverMockConfiguration()?.rumEndpoint,
            telemetrySampleRate: 100
        )
        RUM.enable(with: rumConfiguration)
        RUMMonitor.shared().addAttribute(
            forKey: RUMMultiSceneProbeState.Attribute.runID,
            value: RUMMultiSceneProbeState.runID
        )

        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                customEndpoint: Environment.serverMockConfiguration()?.srEndpoint
            )
        )

        Logs.enable(
            with: .init(customEndpoint: Environment.serverMockConfiguration()?.logsEndpoint)
        )
        Trace.enable(
            with: .init(
                sampleRate: 100,
                service: RUMMultiSceneProbeState.serviceName,
                urlSessionTracking: .init(
                    firstPartyHostsTracing: .traceWithHeaders(
                        hostsWithHeaders: ["multi-scene-probe.invalid": [.datadog, .tracecontext]],
                        sampleRate: 100
                    )
                ),
                eventMapper: { event in
                    RUMMultiSceneProbeState.record(spanEvent: event)
                    return event
                },
                customEndpoint: Environment.serverMockConfiguration()?.tracesEndpoint
            )
        )

        RUMMultiSceneProbeState.record(
            "configured service=\(RUMMultiSceneProbeState.serviceName)"
        )
    }

    func makeRootViewController(
        for windowScene: UIWindowScene,
        session: UISceneSession,
        connectionOptions: UIScene.ConnectionOptions
    ) -> UIViewController? {
        let requestedLabel = connectionOptions.userActivities
            .first?
            .userInfo?[RUMMultiSceneProbeState.Attribute.requestedScene] as? String
        let context = RUMMultiSceneProbeState.register(
            session: session,
            requestedLabel: requestedLabel
        )
        windowScene.userActivity = RUMMultiSceneProbeState.userActivity(for: context)
        RUMMultiSceneProbeState.record(
            "scene connected label=\(context.sceneLabel) native=\(context.sceneSessionID)"
        )
        let root = RUMMultiSceneProbeRootViewController(context: context)
        RUMMultiSceneProbeState.startNetworkRequest(
            context: context,
            networkCase: "scene-connection",
            delay: 0.25
        )
        return root
    }
}

struct RUMMultiSceneProbeContext: Sendable {
    let runID: String
    let sceneLabel: String
    let sceneSessionID: String

    var attributes: [String: Encodable] {
        [
            RUMMultiSceneProbeState.Attribute.runID: runID,
            RUMMultiSceneProbeState.Attribute.sourceScene: sceneLabel,
            RUMMultiSceneProbeState.Attribute.sceneSessionID: sceneSessionID
        ]
    }
}

enum RUMMultiSceneProbeState {
    static let serviceName = "ios-sdk-multi-scene-probe"
    static let activityType = "com.datadoghq.ios-sdk.rum-multi-scene-probe"
    static let runID = ProcessInfo.processInfo.environment["DD_MULTI_SCENE_RUN_ID"]
        ?? UUID().uuidString.lowercased()

    enum Attribute {
        static let runID = "probe.run_id"
        static let sourceScene = "probe.source_scene"
        static let sceneSessionID = "probe.scene_session_id"
        static let requestedScene = "probe.requested_scene"
        static let origin = "probe.origin"
        static let networkCase = "probe.network_case"
        static let requestID = "probe.request_id"
    }

    private static let lock = NSLock()
    private static var contextsBySessionID: [String: RUMMultiSceneProbeContext] = [:]
    private static var nextSceneIndex = 0
    private static var preparedNetworkTasksByScene: [String: URLSessionDataTask] = [:]
    private static var sharedNetworkTask: URLSessionDataTask?
    private static var sharedNetworkUsers: Set<String> = []
    private static let probeLogger = Logger(
        subsystem: "com.datadoghq.ios-sdk.multi-scene-probe",
        category: "probe"
    )
    private static let networkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RUMMultiSceneProbeURLProtocol.self]
            + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }()

    static func register(
        session: UISceneSession,
        requestedLabel: String?
    ) -> RUMMultiSceneProbeContext {
        lock.lock()
        defer { lock.unlock() }

        if let existing = contextsBySessionID[session.persistentIdentifier] {
            return existing
        }

        let sceneLabel = requestedLabel ?? label(for: nextSceneIndex)
        nextSceneIndex += 1
        let context = RUMMultiSceneProbeContext(
            runID: runID,
            sceneLabel: sceneLabel,
            sceneSessionID: session.persistentIdentifier
        )
        contextsBySessionID[session.persistentIdentifier] = context
        return context
    }

    static func context(for session: UISceneSession?) -> RUMMultiSceneProbeContext? {
        guard let session else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        return contextsBySessionID[session.persistentIdentifier]
    }

    static func context(for view: UIView) -> RUMMultiSceneProbeContext? {
        context(for: view.window?.windowScene?.session)
    }

    static func requestNewScene(after context: RUMMultiSceneProbeContext) {
        let requestedLabel: String
        lock.lock()
        requestedLabel = label(for: nextSceneIndex)
        lock.unlock()

        let activity = NSUserActivity(activityType: activityType)
        activity.targetContentIdentifier = UUID().uuidString
        activity.addUserInfoEntries(
            from: [Attribute.requestedScene: requestedLabel]
        )
        record(
            "scene request from=\(context.sceneLabel) requested=\(requestedLabel)"
        )
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil
        ) { error in
            record(
                "scene request failed requested=\(requestedLabel) error=\(type(of: error))"
            )
        }
    }

    static func activateOtherScene(from context: RUMMultiSceneProbeContext) {
        guard let session = UIApplication.shared.openSessions.first(
            where: { $0.persistentIdentifier != context.sceneSessionID }
        ) else {
            record("scene activation ignored from=\(context.sceneLabel) reason=no-other-session")
            return
        }
        let targetLabel = self.context(for: session)?.sceneLabel ?? "unknown"
        record("scene activation from=\(context.sceneLabel) target=\(targetLabel)")
        UIApplication.shared.requestSceneSessionActivation(
            session,
            userActivity: nil,
            options: nil
        ) { error in
            record(
                "scene activation failed target=\(targetLabel) error=\(type(of: error))"
            )
        }
    }

    static func closeScene(context: RUMMultiSceneProbeContext) {
        guard let session = UIApplication.shared.openSessions.first(
            where: { $0.persistentIdentifier == context.sceneSessionID }
        ) else {
            record("scene close ignored label=\(context.sceneLabel) reason=no-open-session")
            return
        }
        closeScene(session: session, context: context)
    }

    static func closeScene(for view: UIView) {
        guard let session = view.window?.windowScene?.session else {
            record("scene close ignored reason=no-window-scene")
            return
        }
        closeScene(session: session, context: context(for: session))
    }

    private static func closeScene(
        session: UISceneSession,
        context: RUMMultiSceneProbeContext?
    ) {
        record("scene close requested label=\(context?.sceneLabel ?? "unknown")")
        UIApplication.shared.requestSceneSessionDestruction(
            session,
            options: nil
        ) { error in
            record(
                "scene close failed label=\(context?.sceneLabel ?? "unknown") error=\(type(of: error))"
            )
        }
    }

    static func userActivity(for context: RUMMultiSceneProbeContext) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.targetContentIdentifier = context.sceneSessionID
        activity.addUserInfoEntries(
            from: [Attribute.requestedScene: context.sceneLabel]
        )
        return activity
    }

    static func networkAttributes(from request: URLRequest) -> [String: Encodable] {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        var attributes: [String: Encodable] = [:]
        if let value = query["dd_run"] { attributes[Attribute.runID] = value }
        if let value = query["dd_scene"] { attributes[Attribute.sourceScene] = value }
        if let value = query["dd_scene_session"] { attributes[Attribute.sceneSessionID] = value }
        if let value = query["dd_case"] { attributes[Attribute.networkCase] = value }
        if let value = query["dd_request"] { attributes[Attribute.requestID] = value }
        return attributes
    }

    static func makeNetworkTask(
        context: RUMMultiSceneProbeContext,
        networkCase: String,
        delay: TimeInterval = 2,
        traceOnly: Bool = false
    ) -> URLSessionDataTask? {
        let requestID = UUID().uuidString.lowercased()
        var components = URLComponents()
        components.scheme = "https"
        components.host = "multi-scene-probe.invalid"
        components.path = traceOnly ? "/trace-only" : "/resource"
        components.queryItems = [
            URLQueryItem(name: "dd_run", value: context.runID),
            URLQueryItem(name: "dd_scene", value: context.sceneLabel),
            URLQueryItem(name: "dd_scene_session", value: context.sceneSessionID),
            URLQueryItem(name: "dd_case", value: networkCase),
            URLQueryItem(name: "dd_request", value: requestID),
            URLQueryItem(name: "dd_delay", value: String(delay))
        ]
        guard let url = components.url else {
            record("network prepare failed source=\(context.sceneLabel) case=\(networkCase)")
            return nil
        }
        let request = URLRequest(url: url)
        record(
            "network prepared source=\(context.sceneLabel) case=\(networkCase) request=\(requestID)"
        )
        return networkSession.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            record(
                "network completed source=\(context.sceneLabel) case=\(networkCase) request=\(requestID) status=\(String(describing: status)) error=\(error.map { String(describing: type(of: $0)) } ?? "nil")"
            )
        }
    }

    static func startNetworkRequest(
        context: RUMMultiSceneProbeContext,
        networkCase: String,
        delay: TimeInterval = 2,
        traceOnly: Bool = false
    ) {
        guard let task = makeNetworkTask(
            context: context,
            networkCase: networkCase,
            delay: delay,
            traceOnly: traceOnly
        ) else {
            return
        }
        record("network resumed source=\(context.sceneLabel) case=\(networkCase)")
        task.resume()
    }

    static func prepareNetworkRequest(
        context: RUMMultiSceneProbeContext,
        networkCase: String
    ) {
        guard let task = makeNetworkTask(
            context: context,
            networkCase: networkCase
        ) else {
            return
        }
        lock.lock()
        let previousTask = preparedNetworkTasksByScene.updateValue(
            task,
            forKey: context.sceneSessionID
        )
        lock.unlock()
        previousTask?.cancel()
    }

    static func resumePreparedNetworkRequest(
        context: RUMMultiSceneProbeContext
    ) -> Bool {
        lock.lock()
        let task = preparedNetworkTasksByScene.removeValue(
            forKey: context.sceneSessionID
        )
        lock.unlock()
        guard let task else {
            return false
        }
        record("network resumed prepared source=\(context.sceneLabel)")
        task.resume()
        return true
    }

    static func useSharedNetworkRequest(context: RUMMultiSceneProbeContext) {
        let taskToStart: URLSessionDataTask?
        let didJoinExisting: Bool
        let users: String
        lock.lock()
        sharedNetworkUsers.insert(context.sceneLabel)
        if sharedNetworkTask == nil {
            sharedNetworkTask = makeNetworkTask(
                context: context,
                networkCase: "shared-request",
                delay: 5
            )
            taskToStart = sharedNetworkTask
            didJoinExisting = false
        } else {
            taskToStart = nil
            didJoinExisting = true
        }
        users = sharedNetworkUsers.sorted().joined(separator: ",")
        lock.unlock()

        record(
            "network shared source=\(context.sceneLabel) users=\(users) joined=\(didJoinExisting)"
        )
        taskToStart?.resume()
    }

    static func record(_ message: String) {
        print("🔬 [RUM Multi-Scene] run=\(runID) \(message)")
        probeLogger.notice("run=\(runID, privacy: .public) \(message, privacy: .public)")
    }

    static func record(viewEvent event: RUMViewEvent) {
        record(
            "payload type=view session=\(event.session.id) view=\(event.view.id) name=\(event.view.name ?? "nil") active=\(String(describing: event.view.isActive))"
        )
    }

    static func record(actionEvent event: RUMActionEvent) {
        record(
            "payload type=action session=\(event.session.id) view=\(event.view.id) action=\(event.action.id) name=\(event.view.name ?? "nil") target=\(event.action.target?.name ?? "nil")"
        )
    }

    static func record(resourceEvent event: RUMResourceEvent) {
        let actionID: String
        switch event.action?.id {
        case .string(let value):
            actionID = value
        case .stringsArray(let values):
            actionID = values.joined(separator: ",")
        case nil:
            actionID = "nil"
        }
        record(
            "payload type=resource session=\(event.session.id) view=\(event.view.id) action=\(actionID) resource=\(event.resource.id) name=\(event.view.name ?? "nil") url=\(event.resource.url)"
        )
    }

    static func record(spanEvent event: SpanEvent) {
        record(
            "payload type=span operation=\(event.operationName) resource=\(event.resource) session=\(event.tags["_dd.session.id"] ?? "nil") view=\(event.tags["_dd.view.id"] ?? "nil") action=\(event.tags["_dd.action.id"] ?? "nil")"
        )
    }

    static func record(errorEvent event: RUMErrorEvent) {
        record(
            "payload type=error session=\(event.session.id) view=\(event.view.id) name=\(event.view.name ?? "nil") message=\(event.error.message)"
        )
    }

    static func record(longTaskEvent event: RUMLongTaskEvent) {
        record(
            "payload type=long_task session=\(event.session.id) view=\(event.view.id) name=\(event.view.name ?? "nil") duration=\(event.longTask.duration)"
        )
    }

    private static func label(for index: Int) -> String {
        if index < 26, let scalar = UnicodeScalar(65 + index) {
            return "scene-\(Character(scalar))"
        }
        return "scene-\(index + 1)"
    }
}

private struct RUMMultiSceneProbeUIKitViewsPredicate: UIKitRUMViewsPredicate {
    private let defaultPredicate = DefaultUIKitRUMViewsPredicate()

    func rumView(for viewController: UIViewController) -> RUMView? {
        guard !(viewController is RUMMultiSceneProbeRootViewController) else {
            return nil
        }
        guard var rumView = defaultPredicate.rumView(for: viewController) else {
            return nil
        }

        if let described = viewController as? RUMMultiSceneProbeViewDescribing {
            rumView.name = described.rumViewName
            rumView.path = described.rumViewPath
        }

        if let context = viewController.viewIfLoaded
            .flatMap(RUMMultiSceneProbeState.context(for:)) {
            rumView.attributes.merge(context.attributes) { _, new in new }
        }
        return rumView
    }
}

private struct RUMMultiSceneProbeUIKitActionsPredicate: UIKitRUMActionsPredicate {
    private let defaultPredicate = DefaultUIKitRUMActionsPredicate()

    func rumAction(targetView: UIView) -> RUMAction? {
        if targetView.accessibilityIdentifier?.contains("filtered-network") == true {
            return nil
        }
        guard var rumAction = defaultPredicate.rumAction(targetView: targetView) else {
            return nil
        }
        if let context = RUMMultiSceneProbeState.context(for: targetView) {
            rumAction.attributes.merge(context.attributes) { _, new in new }
        }
        return rumAction
    }
}

protocol RUMMultiSceneProbeViewDescribing {
    var rumViewName: String { get }
    var rumViewPath: String { get }
}

/// In-process transport for exercising real URLSession creation, resume,
/// interception, suspension, and completion timing without sending probe
/// metadata or trace headers to an external server.
private final class RUMMultiSceneProbeURLProtocol: URLProtocol {
    private var responseWorkItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "multi-scene-probe.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let delay = request.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            .flatMap { components in
                components.queryItems?.first(where: { $0.name == "dd_delay" })?.value
            }
            .flatMap(TimeInterval.init) ?? 0

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.responseWorkItem?.isCancelled == false else {
                return
            }
            guard let url = self.request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                self.client?.urlProtocol(
                    self,
                    didFailWithError: URLError(.badServerResponse)
                )
                return
            }
            self.client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            self.client?.urlProtocol(self, didLoad: Data("{}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        responseWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    override func stopLoading() {
        responseWorkItem?.cancel()
        responseWorkItem = nil
    }
}
