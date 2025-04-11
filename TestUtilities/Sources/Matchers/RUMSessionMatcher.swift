/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if !DD_COMPILED_FOR_INTEGRATION_TESTS
/// This file is compiled both for Unit and Integration tests.
/// * The Unit Tests target can see `Datadog` by `@testable import DatadogCore`.
/// * In Integration Tests target we want to compile `Datadog` in "Release" configuration, so testability is not possible.
/// This compiler statement gives both targets the visibility of `RUMDataModels.swift` either by import or direct compilation.
@testable import DatadogRUM
#endif

/// An error thrown by the `RUMSessionMatcher` if it spots an inconsistency in tracked RUM Session, e.g. when
/// two RUM View events have the same `view.id` but different path (which is not allowed by the RUM product constraints).
struct RUMSessionConsistencyException: Error, CustomStringConvertible {
    let description: String
}

public class RUMSessionMatcher {
    // MARK: - Initialization

    /// Takes the array of `RUMEventMatchers` and groups them by application ID and session ID.
    /// For each distinct session ID, the `RUMSessionMatcher` is created.
    /// Each `RUMSessionMatcher` groups its RUM Events by kind and `ViewVisit`.
    public class func groupMatchersBySessions(_ matchers: [RUMEventMatcher]) throws -> [RUMSessionMatcher] {
        struct Group: Hashable {
            let applicationID: String
            let sessionID: String
        }

        let eventMatchersBySessionID: [Group: [RUMEventMatcher]] = try Dictionary(grouping: matchers) { eventMatcher in
            Group(
                applicationID: try eventMatcher.jsonMatcher.value(forKeyPath: "application.id"),
                sessionID: try eventMatcher.jsonMatcher.value(forKeyPath: "session.id")
            )
        }

        return try eventMatchersBySessionID
            .map { group, eventMatchers in
                try RUMSessionMatcher(
                    applicationID: group.applicationID,
                    sessionID: group.sessionID,
                    sessionEventMatchers: eventMatchers
                )
            }
            .sorted { session1, session2 in
                let startTime1 = session1.views.first?.viewEvents.first?.date ?? 0
                let startTime2 = session2.views.first?.viewEvents.first?.date ?? 0
                return startTime1 < startTime2
            }
    }

    // MARK: - View Visits

    /// Single RUM View visit tracked in this RUM Session.
    /// Groups all the `RUMEvents` send during this visit.
    public class View {
        /// The identifier of all `RUM Views` tracked during this visit.
        public let viewID: String

        init(viewID: String) {
            self.viewID = viewID
        }

        /// The `name` of the visited RUM View.
        /// Corresponds to the "VIEW NAME" in RUM Explorer.
        /// Might be `nil` for events received from Browser SDK.
        public fileprivate(set) var name: String?

        /// The `path` of the visited RUM View.
        /// Corresponds to the "VIEW URL" in RUM Explorer.
        public  fileprivate(set) var path: String = ""

        /// `RUMView` events tracked during this visit.
        public  fileprivate(set) var viewEvents: [RUMViewEvent] = []

        /// `RUMEventMatchers` corresponding to item in `viewEvents`.
        public fileprivate(set) var viewEventMatchers: [RUMEventMatcher] = []

        /// `RUMAction` events tracked during this visit.
        public fileprivate(set) var actionEvents: [RUMActionEvent] = []

        /// `RUMResource` events tracked during this visit.
        public fileprivate(set) var resourceEvents: [RUMResourceEvent] = []

        /// `RUMError` events tracked during this visit.
        public fileprivate(set) var errorEvents: [RUMErrorEvent] = []

        /// `RUMLongTask` events tracked during this visit.
        public fileprivate(set) var longTaskEvents: [RUMLongTaskEvent] = []
    }

    /// RUM application ID for this session.
    public let applicationID: String
    /// The ID of this session in RUM.
    public let sessionID: String

    /// An array of view visits tracked during this RUM session.
    /// Each `ViewVisit` is determined by unique `view.id` and groups all RUM events linked to that `view.id`.'
    public let views: [View]

    /// All RUM events in this session.
    public let allEvents: [RUMEventMatcher]

    public let viewEventMatchers: [RUMEventMatcher]
    public let actionEventMatchers: [RUMEventMatcher]
    public let resourceEventMatchers: [RUMEventMatcher]
    public let errorEventMatchers: [RUMEventMatcher]
    public let longTaskEventMatchers: [RUMEventMatcher]

    /// `RUMView` events tracked in this session.
    let viewEvents: [RUMViewEvent]

    /// `RUMAction` events tracked in this session.
    let actionEvents: [RUMActionEvent]

    /// `RUMResource` events tracked in this session.
    let resourceEvents: [RUMResourceEvent]

    /// `RUMError` events tracked in this session.
    let errorEvents: [RUMErrorEvent]

    /// `RUMLongTask` events tracked in this session.
    let longTaskEvents: [RUMLongTaskEvent]

    private init(applicationID: String, sessionID: String, sessionEventMatchers: [RUMEventMatcher]) throws {
        // Sort events so they follow increasing time order
        let sessionEventOrderedByTime = try sessionEventMatchers.sorted { firstEvent, secondEvent in
            let firstEventTime: Int64 = try firstEvent.jsonMatcher.value(forKeyPath: "date")
            let secondEventTime: Int64 = try secondEvent.jsonMatcher.value(forKeyPath: "date")
            return firstEventTime < secondEventTime
        }

        let eventsMatchersByType: [String: [RUMEventMatcher]] = try Dictionary(grouping: sessionEventOrderedByTime) { eventMatcher in
            try eventMatcher.jsonMatcher.value(forKeyPath: "type") as String
        }

        // Get RUM Events by kind:

        self.applicationID = applicationID
        self.sessionID = sessionID
        self.allEvents = sessionEventMatchers
        self.viewEventMatchers = eventsMatchersByType["view"] ?? []
        self.actionEventMatchers = eventsMatchersByType["action"] ?? []
        self.resourceEventMatchers = eventsMatchersByType["resource"] ?? []
        self.errorEventMatchers = eventsMatchersByType["error"] ?? []
        self.longTaskEventMatchers = eventsMatchersByType["long_task"] ?? []

        let viewEvents: [RUMViewEvent] = try viewEventMatchers.map { matcher in try matcher.model() }

        let actionEvents: [RUMActionEvent] = try actionEventMatchers
            .map { matcher in try matcher.model() }

        let resourceEvents: [RUMResourceEvent] = try resourceEventMatchers
            .map { matcher in try matcher.model() }

        let errorEvents: [RUMErrorEvent] = try errorEventMatchers
            .map { matcher in try matcher.model() }

        let longTaskEvents: [RUMLongTaskEvent] = try longTaskEventMatchers
            .map { matcher in try matcher.model() }

        // Validate each group of events individually
        try validate(rumViewEvents: viewEvents)
        try validate(rumActionEvents: actionEvents)
        try validate(rumResourceEvents: resourceEvents)
        try validate(rumErrorEvents: errorEvents)
        try validate(rumLongTaskEvents: longTaskEvents)

        // Group RUMView events into ViewVisits:
        let uniqueViewIDs = Set(viewEvents.map { $0.view.id })
        let visits = uniqueViewIDs.map { viewID in View(viewID: viewID) }

        var visitsByViewID: [String: View] = [:]
        visits.forEach { visit in visitsByViewID[visit.viewID] = visit }

        // Group RUM Events and their matchers by View Visits:
        try zip(viewEvents, viewEventMatchers).forEach { rumEvent, matcher in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.viewEvents.append(rumEvent)
                visit.viewEventMatchers.append(matcher)
                if visit.name == nil {
                    visit.name = rumEvent.view.name
                } else if visit.name != rumEvent.view.name {
                    throw RUMSessionConsistencyException(
                        description: "The RUM View name: \(rumEvent) is different than other RUM View names for the same `view.id`."
                    )
                }
                if visit.path.isEmpty {
                    visit.path = rumEvent.view.url
                } else if visit.path != rumEvent.view.url {
                    throw RUMSessionConsistencyException(
                        description: "The RUM View url: \(rumEvent) is different than other RUM View urls for the same `view.id`."
                    )
                }
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try actionEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.actionEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try resourceEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.resourceEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try errorEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.errorEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        try longTaskEvents.forEach { rumEvent in
            if let visit = visitsByViewID[rumEvent.view.id] {
                visit.longTaskEvents.append(rumEvent)
            } else {
                throw RUMSessionConsistencyException(
                    description: "Cannot link RUM Event: \(rumEvent) to `RUMSessionMatcher.ViewVisit` by `view.id`."
                )
            }
        }

        // Sort visits by time
        let visitsEventOrderedByTime = visits.sorted { firstVisit, secondVisit in
            let firstVisitTime = firstVisit.viewEvents[0].date
            let secondVisitTime = secondVisit.viewEvents[0].date
            return firstVisitTime < secondVisitTime
        }

        // Sort view events in each visit by document version
        visits.forEach { visit in
            visit.viewEvents = visit.viewEvents.sorted { viewUpdate1, viewUpdate2 in
                viewUpdate1.dd.documentVersion < viewUpdate2.dd.documentVersion
            }
        }

        // Validate ViewVisit's view.isActive for each events
        try visits.forEach { visit in
            var viewIsInactive = false
            try visit.viewEvents.enumerated().forEach { index, viewEvent in
                guard let viewIsActive = viewEvent.view.isActive else {
                    throw RUMSessionConsistencyException(
                        description: "A `RUMSessionMatcher.ViewVisit` can't have an event without the `isActive` parameter set."
                    )
                }

                if viewIsInactive {
                    throw RUMSessionConsistencyException(
                        description: "A `RUMSessionMatcher.ViewVisit` can't have an event after the `View` was marked as inactive."
                    )
                }
                viewIsInactive = !viewIsActive
            }
        }

        self.views = visitsEventOrderedByTime
        self.viewEvents = viewEvents
        self.actionEvents = actionEvents
        self.resourceEvents = resourceEvents
        self.errorEvents = errorEvents
        self.longTaskEvents = longTaskEvents
    }

    /// Checks if this session contains a view with a specific ID.
    /// - Parameter viewID: The ID of the view to check.
    /// - Returns: `true` if a view with the given `viewID` is present in this session; otherwise, `false`.
    public func containsView(with viewID: String) -> Bool {
        let allIDs = Set(views.map { $0.viewID })
        return allIDs.contains(viewID)
    }
}

private func validate(rumViewEvents: [RUMViewEvent]) throws {
    // All view events must use `session.plan` "lite"
    try rumViewEvents.forEach { viewEvent in
        if viewEvent.source == .ios { // validete only mobile events
            try validate(device: viewEvent.device)
            try validate(os: viewEvent.os)
        }
    }
}

private func validate(rumActionEvents: [RUMActionEvent]) throws {
    // All action events must use `session.plan` "lite"
    try rumActionEvents.forEach { actionEvent in
        if actionEvent.source == .ios { // validete only mobile events
            try validate(device: actionEvent.device)
            try validate(os: actionEvent.os)
        }
    }
}

private func validate(rumResourceEvents: [RUMResourceEvent]) throws {
    // All resource events must have unique ID
    let ids = Set(rumResourceEvents.map { $0.resource.id })
    if ids.count != rumResourceEvents.count {
        throw RUMSessionConsistencyException(
            description: "`resource.id` should be unique - found at least two RUMResourceEvents with the same `resource.id`."
        )
    }

    // All resource events must use `session.plan` "lite"
    try rumResourceEvents.forEach { resourceEvent in
        if resourceEvent.source == .ios { // validete only mobile events
            try validate(device: resourceEvent.device)
            try validate(os: resourceEvent.os)
        }
    }
}

private func validate(rumErrorEvents: [RUMErrorEvent]) throws {
    // All error events must use `session.plan` "lite"
    try rumErrorEvents.forEach { errorEvent in
        if errorEvent.source == .ios { // validete only mobile events
            try validate(device: errorEvent.device)
            try validate(os: errorEvent.os)
        }
    }
}

private func validate(rumLongTaskEvents: [RUMLongTaskEvent]) throws {
    // All error events must use `session.plan` "lite"
    try rumLongTaskEvents.forEach { longTaskEvent in
        if longTaskEvent.source == .ios { // validete only mobile events
            try validate(device: longTaskEvent.device)
            try validate(os: longTaskEvent.os)
        }
    }
}

private func validate(device: RUMDevice?) throws {
    guard let device = device else {
        throw RUMSessionConsistencyException(
            description: "All RUM events must include device information"
        )
    }
    #if DD_COMPILED_FOR_INTEGRATION_TESTS
    try strictValidate(device: device)
    #endif
}

private func validate(os: RUMOperatingSystem?) throws {
    guard let os = os else {
        throw RUMSessionConsistencyException(
            description: "All RUM events must include OS information"
        )
    }
    #if DD_COMPILED_FOR_INTEGRATION_TESTS
    try strictValidate(os: os)
    #endif
}

// MARK: - Strict Validation (in Integration Tests)

/// Performs strict validation of `RUMDevice` for integration tests.
/// It asserts that all values make sense for current environment.
private func strictValidate(device: RUMDevice) throws {
    guard device.brand == "Apple" else {
        throw RUMSessionConsistencyException(description: "All RUM events must use `device.brand = Apple` (got `\(device.brand ?? "nil")` instead)")
    }
    #if os(iOS)
    guard device.type == .mobile || device.type == .tablet else {
        throw RUMSessionConsistencyException(
            description: "When running on iOS or iPadOS, the `device.type` must be `.mobile` or `.tablet` (got `\(device.type)` instead)"
        )
    }
    let prefixes = ["iPhone", "iPod", "iPad"]
    guard prefixes.contains(where: { device.name?.hasPrefix($0) ?? false }) else {
        throw RUMSessionConsistencyException(
            description: "When running on iOS or iPadOS, the `device.name` must start with one of: \(prefixes) (got `\(device.name ?? "nil")` instead)"
        )
    }
    guard prefixes.contains(where: { device.model?.hasPrefix($0) ?? false }) else {
        throw RUMSessionConsistencyException(
            description: "When running on iOS or iPadOS, the `device.model` must start with one of: \(prefixes) (got `\(device.model ?? "nil")` instead)"
        )
    }
    #else
    guard device.type != .tv else {
        throw RUMSessionConsistencyException(
            description: "When running on tvOS, the `device.type` must be `.tv` (got `\(device.type)` instead)"
        )
    }
    guard device.name == "Apple TV" else {
        throw RUMSessionConsistencyException(
            description: "When running on tvOS, the `device.name` must be `Apple TV` (got `\(device.name ?? "nil")` instead)"
        )
    }
    guard device.model?.hasPrefix("AppleTV") ?? false else {
        throw RUMSessionConsistencyException(
            description: "When running on tvOS, the `device.model` must start with `AppleTV` (got `\(device.model ?? "nil")` instead)"
        )
    }
    #endif
}

/// Performs strict validation of `RUMOperatingSystem` for integration tests.
/// It asserts that all values make sense for current environment.
private func strictValidate(os: RUMOperatingSystem) throws {
    #if os(iOS)
    guard os.name == "iOS" || os.name == "iPadOS" else {
        throw RUMSessionConsistencyException(
            description: "When running on iOS or iPadOS the `os.name` must be either 'iOS' or 'iPadOS'"
        )
    }
    #else
    guard os.name == "tvOS" else {
        throw RUMSessionConsistencyException(
            description: "When running on tvOS the `os.name` must be 'tvOS'"
        )
    }
    #endif
}

// MARK: - Matching

extension Array where Element == RUMSessionMatcher {
    /// Returns the only session in this array.
    /// Throws if there is more than one session or the array has no elements.
    public func takeSingle() throws -> RUMSessionMatcher {
        guard !isEmpty else {
            throw RUMSessionConsistencyException(description: "There are no sessions in this array")
        }
        guard count == 1 else {
            throw RUMSessionConsistencyException(description: "Expected to find only one session, but found \(count)")
        }
        return self[0]
    }

    /// Returns the only two sessions in this array.
    /// Throws if there are more or less than 2 sessions in this array.
    public func takeTwo() throws -> (RUMSessionMatcher, RUMSessionMatcher) {
        guard count == 2 else {
            throw RUMSessionConsistencyException(description: "Expected 2 sessions, but found \(count)")
        }
        return (self[0], self[1])
    }
}

extension Array where Element == RUMSessionMatcher.View {
    /// Returns list of views by dropping "application launch" view.
    /// Throws if "application launch" is not the first view in this array.
    ///
    /// Use it to explicitly ignore the "application launch" view with running strict check of its existence.
    public func dropApplicationLaunchView() throws -> [RUMSessionMatcher.View] {
        guard let first = first else {
            throw RUMSessionConsistencyException(description: "Cannot drop 'application launch' view in empty array")
        }
        guard first.isApplicationLaunchView() else {
            throw RUMSessionConsistencyException(description: "The first view in this array is not 'application launch' view (\(first.name ?? "???")")
        }
        return Array(dropFirst())
    }
}

extension RUMSessionMatcher.View {
    /// Whether this is "application launch" view.
    public func isApplicationLaunchView() -> Bool {
        return name == "ApplicationLaunch" && path == "com/datadog/application-launch/view"
    }

    /// Whether this is "background" view.
    public func isBackgroundView() -> Bool {
        return name == "Background" && path == "com/datadog/background/view"
    }
}

private extension Date {
    init(millisecondsSince1970: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1_000)
    }
}

private extension TimeInterval {
    init(fromNanoseconds nanoseconds: Int64) {
        self = TimeInterval(nanoseconds) / 1_000_000_000
    }
}

extension RUMSessionMatcher {
    /// Asserts that all events in this session have certain `sessionPrecondition` set.
    /// Throws if there are no views in this session.
    public func has(sessionPrecondition: RUMSessionPrecondition) throws -> Bool {
        guard !views.isEmpty else {
            throw RUMSessionConsistencyException(description: "There are no views in this session")
        }

        for view in views {
            guard view.viewEvents.allSatisfy({ $0.dd.session?.sessionPrecondition == sessionPrecondition }) else {
                return false
            }
            guard view.actionEvents.allSatisfy({ $0.dd.session?.sessionPrecondition == sessionPrecondition }) else {
                return false
            }
            guard view.resourceEvents.allSatisfy({ $0.dd.session?.sessionPrecondition == sessionPrecondition }) else {
                return false
            }
            guard view.errorEvents.allSatisfy({ $0.dd.session?.sessionPrecondition == sessionPrecondition }) else {
                return false
            }
            guard view.longTaskEvents.allSatisfy({ $0.dd.session?.sessionPrecondition == sessionPrecondition }) else {
                return false
            }
        }

        return true
    }
}

// MARK: - Debugging

extension RUMSessionMatcher.View {
    /// The start of this view (as timestamp; milliseconds) defined as the start timestamp of the earliest view event in this view.
    var startTimestampMs: Int64 { viewEvents.map({ $0.date }).min() ?? 0 }
}

extension RUMSessionMatcher: CustomStringConvertible {
    public var description: String { renderSession() }

    /// The start of this session (as timestamp; milliseconds) defined as the start timestamp of the earliest view in this session.
    private var sessionStartTimestampMs: Int64 { viewEvents.map({ $0.date }).min() ?? 0 }

    /// The start of this session (as timestamp; nanoseconds) defined as the start timestamp of the earliest view in this session.
    private var sessionStartTimestampNs: Int64 { sessionStartTimestampMs * 1_000_000 }

    /// The end of this session (as timestamp; nanoseconds) defined as the end timestamp of the latest view in this session.
    private var sessionEndTimestampNs: Int64 { viewEvents.map({ $0.date * 1_000_000 + $0.view.timeSpent }).max() ?? 0 }

    private func renderSession() -> String {
        var output = renderBox(string: "🎞 RUM session")
        output += renderAttributesBox(
            attributes: [
                ("application.id", applicationID),
                ("id", sessionID),
                ("views.count", "\(views.count)"),
                ("start", prettyDate(timestampMs: sessionStartTimestampMs)),
                ("duration", pretty(nanoseconds: sessionEndTimestampNs - sessionStartTimestampNs)),
            ]
        )
        views.forEach { view in
            output += render(view: view)
        }
        output += renderClosingLine()
        return output
    }

    private func render(view: View) -> String {
        guard let lastViewEvent = view.viewEvents.last else {
            return renderBox(string: "⛔️ Invalid View - it has no view events")
        }

        var output = renderBox(string: "📸 RUM View (\(view.name ?? "nil"))")
        output += renderAttributesBox(
            attributes: [
                ("name", view.name ?? "nil"),
                ("id", view.viewID),
                ("date", prettyDate(timestampMs: lastViewEvent.date)),
                ("date (relative in session)", pretty(milliseconds: lastViewEvent.date - sessionStartTimestampMs)),
                ("duration", pretty(nanoseconds: lastViewEvent.view.timeSpent)),
                ("event counts", "view (\(view.viewEvents.count)), action (\(view.actionEvents.count)), resource (\(view.resourceEvents.count)), error (\(view.errorEvents.count)), long task (\(view.longTaskEvents.count))"),
            ]
        )

        for action in view.actionEvents {
            output += renderEmptyLine()
            output += render(event: action, in: view)
        }

        for resource in view.resourceEvents {
            output += renderEmptyLine()
            output += render(event: resource, in: view)
        }

        for error in view.errorEvents {
            output += renderEmptyLine()
            output += render(event: error, in: view)
        }

        for longTask in view.longTaskEvents {
            output += renderEmptyLine()
            output += render(event: longTask, in: view)
        }

        output += renderEmptyLine()
        return output
    }

    private func render(event: RUMActionEvent, in view: View) -> String {
        var output = renderAttributesBox(attributes: [("▶️ RUM Action", "")], indentationLevel: 2)
        output += renderAttributesBox(
            attributes: [
                ("date (relative in view)", pretty(milliseconds: event.date - view.startTimestampMs)),
                ("name", event.action.target?.name ?? "nil"),
                ("type", "\(event.action.type)"),
                ("loading.time", "\(event.action.loadingTime.flatMap({ pretty(nanoseconds: $0) }) ?? "nil")"),
            ],
            prefix: "→",
            indentationLevel: 3
        )
        return output
    }

    private func render(event: RUMResourceEvent, in view: View) -> String {
        var output = renderAttributesBox(attributes: [("🌎 RUM Resource", "")], indentationLevel: 2)
        output += renderAttributesBox(
            attributes: [
                ("date (relative in view)", pretty(milliseconds: event.date - view.startTimestampMs)),
                ("url", event.resource.url),
                ("method", "\(event.resource.method.flatMap({ "\($0.rawValue)" }) ?? "nil")"),
                ("status.code", "\(event.resource.statusCode.flatMap({ "\($0)" }) ?? "nil")"),
            ],
            prefix: "→",
            indentationLevel: 3
        )
        return output
    }

    private func render(event: RUMErrorEvent, in view: View) -> String {
        var output = renderAttributesBox(attributes: [("🧯 RUM Error", "")], indentationLevel: 2)
        output += renderAttributesBox(
            attributes: [
                ("date (relative in view)", pretty(milliseconds: event.date - view.startTimestampMs)),
                ("message", event.error.message),
                ("type", event.error.type ?? "nil"),
            ],
            prefix: "→",
            indentationLevel: 3
        )
        return output
    }

    private func render(event: RUMLongTaskEvent, in view: View) -> String {
        var output = renderAttributesBox(attributes: [("🐌 RUM Long Task", "")], indentationLevel: 2)
        output += renderAttributesBox(
            attributes: [
                ("date (relative in view)", pretty(milliseconds: event.date - view.startTimestampMs)),
                ("duration", pretty(nanoseconds: event.longTask.duration)),
            ],
            prefix: "→",
            indentationLevel: 3
        )
        return output
    }

    // MARK: - Rendering helpers

    private static let rendererWidth = 90

    private func renderBox(string: String) -> String {
        let width = RUMSessionMatcher.rendererWidth
        let horizontalBorder1 = "+" + String(repeating: "-", count: width - 2) + "+"
        let horizontalBorder2 = "|" + String(repeating: "-", count: width - 2) + "|"
        let visualWidth = (string as NSString).length
        let padding = (width - 2 - visualWidth) / 2
        let leftPadding = String(repeating: " ", count: max(0, padding))
        let rightPadding = String(repeating: " ", count: max(0, width - 2 - visualWidth - padding))

        let contentLine = "|\(leftPadding)\(string)\(rightPadding)|"

        return """
        \(horizontalBorder1)
        \(contentLine)
        \(horizontalBorder2)\n
        """
    }

    private func renderAttributesBox(attributes: [(String, String)], prefix: String = "", indentationLevel: Int = 0) -> String {
        let width = RUMSessionMatcher.rendererWidth
        let indentation = String(repeating: " ", count: indentationLevel)

        let contentLines = attributes.map { key, value in
            let lineContent = "\(indentation)\(prefix) \(key): \(value)"
            let visualWidth = (lineContent as NSString).length
            let padding = max(0, width - 2 - visualWidth)
            let rightPadding = String(repeating: " ", count: padding)
            return "|\(lineContent)\(rightPadding)|"
        }

        return """
        \(contentLines.joined(separator: "\n"))\n
        """
    }

    private func renderEmptyLine() -> String {
        let width = RUMSessionMatcher.rendererWidth
        let horizontalBorder = "|" + String(repeating: " ", count: width - 2) + "|"
        return horizontalBorder + "\n"
    }

    private func renderClosingLine() -> String {
        let width = RUMSessionMatcher.rendererWidth
        let horizontalBorder = "+" + String(repeating: "-", count: width - 2) + "+"
        return horizontalBorder + "\n"
    }

    private func pretty(milliseconds: Int64) -> String {
        pretty(nanoseconds: milliseconds * 1_000_000)
    }

    private func pretty(nanoseconds: Int64) -> String {
        if nanoseconds >= 1_000_000_000 {
            let seconds = round((Double(nanoseconds) / 1_000_000_000) * 100) / 100
            return "\(seconds)s"
        } else if nanoseconds >= 1_000_000 {
            let milliseconds = round((Double(nanoseconds) / 1_000_000) * 100) / 100
            return "\(milliseconds)ms"
        } else {
            return "\(nanoseconds)ns"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private func prettyDate(timestampMs: Int64) -> String {
        let timestampSec = TimeInterval(timestampMs) / 1_000
        let date = Date(timeIntervalSince1970: timestampSec)
        return RUMSessionMatcher.dateFormatter.string(from: date)
    }
}
