/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public class RUMMonitor: RUMMonitorInternal {
    /// The root scope of RUM monitoring.
    internal let applicationScope: RUMScope
    /// Queue for processing RUM events off the main thread..
    internal let queue: DispatchQueue

    // MARK: - Initialization

    // TODO: RUMM-600 `RUMMonitor` initialization API
    public static func initialize(rumApplicationID: String) -> RUMMonitor {
        guard let rumFeature = RUMFeature.instance else {
            // TODO: RUMM-600 `RUMMonitor` initialization API
            fatalError("RUMFeature not initialized")
        }

        return RUMMonitor(rumFeature: rumFeature, rumApplicationID: rumApplicationID)
    }

    internal convenience init(rumFeature: RUMFeature, rumApplicationID: String) {
        self.init(
            applicationScope: RUMApplicationScope(
                rumApplicationID: rumApplicationID,
                eventBuilder: RUMEventBuilder(
                    userInfoProvider: rumFeature.userInfoProvider,
                    networkConnectionInfoProvider: rumFeature.networkConnectionInfoProvider,
                    carrierInfoProvider: rumFeature.carrierInfoProvider
                ),
                eventOutput: RUMEventFileOutput(
                    fileWriter: rumFeature.storage.writer
                )
            ),
            queue: DispatchQueue(
                label: "com.datadoghq.rum-monitor",
                target: .global(qos: .userInteractive)
            )
        )
    }

    internal init(applicationScope: RUMScope, queue: DispatchQueue) {
        self.applicationScope = applicationScope
        self.queue = queue
    }

    // MARK: - RUMMonitorInternal

    func start(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .startView(id: id, attributes: attributes))
    }

    func stop(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .stopView(id: id, attributes: attributes))
    }

    func addViewError(message: String, error: Error?, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .addCurrentViewError(message: message, error: error, attributes: attributes))
    }

    func start(resource resourceName: String, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .startResource(resourceName: resourceName, attributes: attributes))
    }

    func stop(resource resourceName: String, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .stopResource(resourceName: resourceName, attributes: attributes))
    }

    func stop(resource resourceName: String, withError error: Error, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .stopResourceWithError(resourceName: resourceName, error: error, attributes: attributes))
    }

    func start(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .startUserAction(userAction: userAction, attributes: attributes))
    }

    func stop(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .stopUserAction(userAction: userAction, attributes: attributes))
    }

    func add(userAction: RUMUserAction, attributes: [AttributeKey: AttributeValue]?) {
        process(command: .addUserAction(userAction: userAction, attributes: attributes))
    }

    // MARK: - Private

    private func process(command: RUMCommand) {
        queue.async {
            _ = self.applicationScope.process(command: command)
        }
    }

    // MARK: - TODO: RUMM-585 Temporary APIs to remove

    public func sendFakeViewEvent(viewURL: String) {
        guard let rumFeature = RUMFeature.instance else {
            fatalError("RUMFeature must be initialized.")
        }

        let dataModel = RUMViewEvent(
            date: Date(timeIntervalSinceNow: -1).timeIntervalSince1970.toMilliseconds,
            application: .init(id: applicationScope.context.rumApplicationID),
            session: .init(id: UUID().uuidString.lowercased(), type: "user"),
            view: .init(
                id: UUID().uuidString.lowercased(),
                url: viewURL,
                timeSpent: TimeInterval(0.5).toNanoseconds,
                action: .init(count: 0),
                error: .init(count: 0),
                resource: .init(count: 0)
            ),
            dd: .init(documentVersion: 1)
        )

        let builder = RUMEventBuilder(
            userInfoProvider: rumFeature.userInfoProvider,
            networkConnectionInfoProvider: rumFeature.networkConnectionInfoProvider,
            carrierInfoProvider: rumFeature.carrierInfoProvider
        )

        let event = builder.createRUMEvent(with: dataModel, attributes: nil)

        rumFeature.storage.writer.write(value: event)
    }
}
