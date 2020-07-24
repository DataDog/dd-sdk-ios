/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMResourceScope: RUMScope {
    // MARK: - Initialization

    // TODO: RUMM-597: Consider using `parent: RUMContextProvider`
    private unowned let parent: RUMScope
    private let dependencies: RUMScopeDependencies

    /// The name used to identify this Resource.
    private(set) var resourceName: String
    /// Resource attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]

    /// The Resource url.
    private var resourceURL: String
    /// The start time of this Resource loading.
    private var resourceLoadingStartTime: Date
    /// The HTTP method used to load this Resource.
    private var resourceHTTPMethod: String

    init(
        parent: RUMScope,
        dependencies: RUMScopeDependencies,
        resourceName: String,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        url: String,
        httpMethod: String
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.resourceName = resourceName
        self.attributes = attributes
        self.resourceURL = url
        self.resourceLoadingStartTime = startTime
        self.resourceHTTPMethod = httpMethod
    }

    // MARK: - RUMScope

    var context: RUMContext {
        return parent.context
    }

    func process(command: RUMCommand) -> Bool {
        switch command {
        case let command as RUMStopResourceCommand where command.resourceName == resourceName:
            stopResource(on: command)
            return false
        case let command as RUMStopResourceWithErrorCommand where command.resourceName == resourceName:
            stopResource(on: command)
            return false
        default:
            break
        }
        return true
    }

    // MARK: - RUMCommands Processing

    private func stopResource(on command: RUMStopResourceCommand) {
        sendResourceEvent(on: command)
    }

    private func stopResource(on command: RUMStopResourceWithErrorCommand) {
        sendErrorEvent(on: command)
    }

    // MARK: - Sending RUM Events

    private func sendResourceEvent(on command: RUMStopResourceCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMResourceEvent(
            date: command.time.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: context.activeViewID.orNull.toString,
                url: context.activeViewURI ?? ""
            ),
            resource: .init(
                type: command.type,
                url: resourceURL,
                method: resourceHTTPMethod,
                statusCode: command.httpStatusCode,
                duration: command.time.timeIntervalSince(resourceLoadingStartTime).toNanoseconds,
                size: command.size
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toString)
            },
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMErrorEvent(
            date: command.time.timeIntervalSince1970.toMilliseconds,
            application: .init(id: context.rumApplicationID),
            session: .init(id: context.sessionID.toString, type: "user"),
            view: .init(
                id: context.activeViewID.orNull.toString,
                url: context.activeViewURI ?? ""
            ),
            error: .init(
                message: command.errorMessage,
                source: command.errorSource,
                resource: .init(
                    method: resourceHTTPMethod,
                    statusCode: command.httpStatusCode ?? 0,
                    url: resourceURL
                )
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toString)
            },
            dd: .init()
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }
}
