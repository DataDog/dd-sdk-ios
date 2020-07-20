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

    /// This session UUID.
    private var sessionUUID: UUID
    /// The start time of this session.
    private var sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this session.
    private var lastInteractionTime: Date

    init(
        parent: RUMScope,
        dependencies: RUMScopeDependencies
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.sessionUUID = UUID()
        self.sessionStartTime = dependencies.dateProvider.currentDate()
        self.lastInteractionTime = self.sessionStartTime
    }

    // MARK: - RUMScope

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionUUID
        return context
    }

    func process(command: RUMCommand) -> Bool {
        if timedOutOrExpired() {
            return true // end session
        }

        switch command {
        case .startView:
            // TODO: RUMM-519 Move to `RUMViewScope`
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
                id: UUID().uuidString.lowercased(),
                type: "application_start"
            ),
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: nil)
        dependencies.eventOutput.write(rumEvent: event)

        didSendApplicationStartAction = true
    }

    // MARK: - Private

    private func timedOutOrExpired() -> Bool {
        let currentTime = dependencies.dateProvider.currentDate()

        let timeElapsedSinceLastInteraction = currentTime.timeIntervalSince(lastInteractionTime)
        let timedOut = timeElapsedSinceLastInteraction >= Constants.sessionTimeoutDuration

        let sessionDuration = currentTime.timeIntervalSince(sessionStartTime)
        let expired = sessionDuration >= Constants.sessionMaxDuration

        return timedOut || expired
    }
}
