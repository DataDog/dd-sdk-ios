/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMSessionScope: RUMScope {
    struct Constants {
        /// If no interaction is registered within this period, a new session is started.
        static let sessionTimeoutDuration: TimeInterval = 15 * 60 // 15 minutes
        /// Maximum duration of a session. If it gets exceeded, a new session is started.
        static let sessionMaxDuration: TimeInterval = 4 * 60 * 60 // 4 hours
    }

    // MARK: - Initialization

    unowned let parent: RUMScope
    private let dependencies: RUMScopeDependencies

    /// Current session ID. May change due to inactivity or when exceeding max duration.
    private var sessionID: UUID?
    /// The start time of current session.
    private var sessionStartTime: Date?
    /// Time of the last processed RUM command.
    private var lastInteractionTime: Date?

    init(
        parent: RUMApplicationScope,
        dependencies: RUMScopeDependencies
    ) {
        self.parent = parent
        self.dependencies = dependencies
    }

    // MARK: - RUMScope

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionID ?? parent.context.sessionID
        return context
    }

    func process(command: RUMCommand) -> Bool {
        startNewSessionIfNeeded()

        switch command {
        case .startView:
            sendApplicationStartActionOnlyOnce()
        default:
            break
        }

        lastInteractionTime = dependencies.dateProvider.currentDate()
        return false
    }

    // MARK: - Sending RUM Events

    /// Tracks if the `application_start` RUM action was already sent.
    private var didSendApplicationStartAction = false

    private func sendApplicationStartActionOnlyOnce() {
        guard !didSendApplicationStartAction else {
            return
        }

        let eventData = RUMActionEvent(
            date: Date().timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: UUID().uuidString.lowercased(), type: "user"),
            view: .init(
                // The `application_start` event uses null UUID for its `view.id`
                id: RUMApplicationScope.Constants.nullUUID.uuidString.lowercased(),
                // The `application_start` event uses empty string for its `view.url`
                url: ""
            ),
            action: .init(
                type: "application_start"
            ),
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: nil)
        dependencies.eventOutput.write(rumEvent: event)

        didSendApplicationStartAction = true
    }

    // MARK: - Private

    private func startNewSessionIfNeeded() {
        let currentTime = dependencies.dateProvider.currentDate()

        guard sessionID != nil,
              let sessionStartTime = sessionStartTime,
              let lastInteractionTime = lastInteractionTime
        else {
            // No session was created, start the first one:
            self.sessionID = UUID()
            self.sessionStartTime = currentTime
            return
        }

        let timeElapsedSinceLastInteraction = currentTime.timeIntervalSince(lastInteractionTime)
        let wasInactiveTooLong = timeElapsedSinceLastInteraction >= Constants.sessionTimeoutDuration

        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let isLastingTooLong = sessionDuration >= Constants.sessionMaxDuration

        if wasInactiveTooLong || isLastingTooLong {
            // start new session
            self.sessionID = UUID()
            self.sessionStartTime = currentTime
        }
    }
}
