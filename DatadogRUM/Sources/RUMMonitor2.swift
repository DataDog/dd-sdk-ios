/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

public class RUMMonitor {
    public static func shared(in core: DatadogCoreProtocol = CoreRegistry.default) -> RUMMonitorProtocol {
        do {
            guard !(core is NOPDatadogCore) else {
                throw ProgrammerError(
                    description: "Datadog SDK must be initialized and RUM feature must be enabled before calling `RUMMonitor.shared(in:)`."
                )
            }
            guard let feature = core.get(feature: DatadogRUMFeature.self) else {
                throw ProgrammerError(
                    description: "RUM feature must be enabled before calling `RUMMonitor.shared(in:)`."
                )
            }

            return feature.monitor
        } catch {
            consolePrint("\(error)")
            return NOPRUMMonitor()
        }
    }
}

internal class Monitor: RUMCommandSubscriber {
    let scopes: RUMApplicationScope
    let dateProvider: DateProvider
    let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )

    private weak var core: DatadogCoreProtocol?
    private var attributes: [AttributeKey: AttributeValue] = [:]
    private var debugging: RUMDebugging? = nil

    init(
        core: DatadogCoreProtocol,
        dependencies: RUMScopeDependencies,
        dateProvider: DateProvider
    ) {
        self.core = core
        self.scopes = RUMApplicationScope(dependencies: dependencies)
        self.dateProvider = dateProvider
    }

    func setDebugging(enabled: Bool) {
        debugging = enabled ? RUMDebugging() : nil
        debugging?.debug(applicationScope: scopes)
    }

    func process(command: RUMCommand) {
        // process command in event context
        core?.scope(for: RUMFeature.name)?.eventWriteContext { context, writer in
            self.queue.sync {
                let transformedCommand = self.transform(command: command)

                _ = self.scopes.process(command: transformedCommand, context: context, writer: writer)

                if let debugging = self.debugging {
                    debugging.debug(applicationScope: self.scopes)
                }
            }
        }

        // update the core context with rum context
        core?.set(feature: RUMFeature.name, attributes: {
            self.queue.sync {
                let context = self.scopes.activeSession?.viewScopes.last?.context ??
                                self.scopes.activeSession?.context ??
                                self.scopes.context

                guard context.sessionID != .nullUUID else {
                    // if Session was sampled or not yet started
                    return [:]
                }

                return [
                    RUMContextAttributes.ids: [
                        RUMContextAttributes.IDs.applicationID: context.rumApplicationID,
                        RUMContextAttributes.IDs.sessionID: context.sessionID.rawValue.uuidString.lowercased(),
                        RUMContextAttributes.IDs.viewID: context.activeViewID?.rawValue.uuidString.lowercased(),
                        RUMContextAttributes.IDs.userActionID: context.activeUserActionID?.rawValue.uuidString.lowercased(),
                    ],
                    RUMContextAttributes.serverTimeOffset: self.scopes.activeSession?.viewScopes.last?.serverTimeOffset

                ]
            }
        })
    }

    // TODO: RUMM-896
    // transform() is extracted from process since process() cannot be tested currently
    // once we can mock ApplicationScope, we can test process()
    // then we can remove transform()
    //
    // NOTE: transform() calls self.rumAttributes outside of queue
    // therefore it should be removed once process() is testable
    func transform(command: RUMCommand) -> RUMCommand {
        var mutableCommand = command

        var combinedUserAttributes = attributes
        combinedUserAttributes.merge(rumCommandAttributes: command.attributes)

        if let customTimestampInMiliseconds = combinedUserAttributes.removeValue(forKey: CrossPlatformAttributes.timestampInMilliseconds) as? Int64 {
            let customTimeInterval = TimeInterval(fromMilliseconds: customTimestampInMiliseconds)
            mutableCommand.time = Date(timeIntervalSince1970: customTimeInterval)
        }

        mutableCommand.attributes = combinedUserAttributes

        return mutableCommand
    }
}

extension Monitor: RUMMonitorProtocol {
    // MARK: - attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        queue.async {
            self.attributes[key] = value
        }
    }

    func removeAttribute(forKey key: AttributeKey) {
        queue.async {
            self.attributes[key] = nil
        }
    }

    // MARK: - session

    func stopSession() {
        process(command: RUMStopSessionCommand(time: dateProvider.now))
    }

    // MARK: - views

    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: viewController,
                name: name,
                path: nil,
                attributes: attributes
            )
        )
    }

    func stopView(viewController: UIViewController, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: viewController
            )
        )
    }

    func startView(key: String, name: String?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: key,
                name: name ?? key,
                path: key,
                attributes: attributes
            )
        )
    }

    func stopView(key: String, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: key
            )
        )
    }

    // MARK: - custom timings

    func addTiming(name: String) {
        process(
            command: RUMAddViewTimingCommand(
                time: dateProvider.now,
                attributes: [:],
                timingName: name
            )
        )
    }

    // MARK: - errors

    func addError(message: String, type: String?, stack: String?, source: RUMErrorSource, attributes: [AttributeKey : AttributeValue], file: StaticString?, line: UInt?) {
        let stack: String? = stack ?? {
            if let file = file,
               let fileName = "\(file)".split(separator: "/").last,
               let line = line {
                return "\(fileName):\(line)"
            }
            return nil
        }()
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: RUMInternalErrorSource(source),
                attributes: attributes
            )
        )
    }

    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                attributes: attributes
            )
        )
    }

    // MARK: - resources

    func startResourceLoading(resourceKey: String, request: URLRequest, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: request.url?.absoluteString ?? "unknown_url",
                httpMethod: RUMMethod(httpMethod: request.httpMethod),
                kind: RUMResourceType(request: request),
                spanContext: nil
            )
        )
    }

    func startResourceLoading(resourceKey: String, url: URL, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: url.absoluteString,
                httpMethod: .get,
                kind: nil,
                spanContext: nil
            )
        )
    }

    func startResourceLoading(resourceKey: String, httpMethod: RUMMethod, urlString: String, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: urlString,
                httpMethod: httpMethod,
                kind: nil,
                spanContext: nil
            )
        )
    }

    func addResourceMetrics(resourceKey: String, metrics: URLSessionTaskMetrics, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                metrics: ResourceMetrics(taskMetrics: metrics)
            )
        )
    }

    func addResourceMetrics(resourceKey: String, fetch: (start: Date, end: Date), redirection: (start: Date, end: Date)?, dns: (start: Date, end: Date)?, connect: (start: Date, end: Date)?, ssl: (start: Date, end: Date)?, firstByte: (start: Date, end: Date)?, download: (start: Date, end: Date)?, responseSize: Int64?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                metrics: ResourceMetrics(
                    fetch: ResourceMetrics.DateInterval(start: fetch.start, end: fetch.end),
                    redirection: ResourceMetrics.DateInterval.create(start: redirection?.start, end: redirection?.end),
                    dns: ResourceMetrics.DateInterval.create(start: dns?.start, end: dns?.end),
                    connect: ResourceMetrics.DateInterval.create(start: connect?.start, end: connect?.end),
                    ssl: ResourceMetrics.DateInterval.create(start: ssl?.start, end: ssl?.end),
                    firstByte: ResourceMetrics.DateInterval.create(start: firstByte?.start, end: firstByte?.end),
                    download: ResourceMetrics.DateInterval.create(start: download?.start, end: download?.end),
                    responseSize: responseSize
                )
            )
        )
    }

    func stopResourceLoading(resourceKey: String, response: URLResponse, size: Int64?, attributes: [AttributeKey : AttributeValue]) {
        let resourceKind: RUMResourceType
        var statusCode: Int?

        if let response = response as? HTTPURLResponse {
            resourceKind = RUMResourceType(response: response)
            statusCode = response.statusCode
        } else {
            resourceKind = .xhr
        }

        process(
            command: RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                kind: resourceKind,
                httpStatusCode: statusCode,
                size: size
            )
        )
    }

    func stopResourceLoading(resourceKey: String, statusCode: Int?, kind: RUMResourceType, size: Int64?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                kind: kind,
                httpStatusCode: statusCode,
                size: size
            )
        )
    }

    func stopResourceLoadingWithError(resourceKey: String, error: Error, response: URLResponse?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                error: error,
                source: .network,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
                attributes: attributes
            )
        )
    }

    func stopResourceLoadingWithError(resourceKey: String, errorMessage: String, type: String?, response: URLResponse?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                message: errorMessage,
                type: type,
                source: .network,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
                attributes: attributes
            )
        )
    }

    // MARK: - actions

    func addUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    func startUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    func stopUserAction(type: RUMUserActionType, name: String?, attributes: [AttributeKey : AttributeValue]) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    // MARK: - feature flags

    func addFeatureFlagEvaluation(name: String, value: Encodable) {
        process(
            command: RUMAddFeatureFlagEvaluationCommand(
                time: dateProvider.now,
                name: name,
                value: value
            )
        )
    }
}

extension Monitor {
    func notifySDKInit() {
        process(
            command: RUMSDKInitCommand(time: dateProvider.now)
        )
    }

    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: source,
                attributes: attributes
            )
        )
    }
}
