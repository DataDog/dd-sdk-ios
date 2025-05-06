/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Defines keys referencing RUM messages supported on the bus.
internal enum LoggingMessageKeys {
    /// The key references a crash message.
    static let crash = "crash"
}

/// Receiver to consume a Log message
internal struct LogMessageReceiver: FeatureMessageReceiver {
    /// The log event mapper
    let logEventMapper: LogEventMapper?

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(log as LogMessage) = message else {
            return false
        }

        core.scope(for: LogsFeature.self).eventWriteContext { context, writer in
            let builder = LogEventBuilder(
                service: log.service ?? context.service,
                loggerName: log.logger,
                networkInfoEnabled: log.networkInfoEnabled ?? false,
                eventMapper: logEventMapper
            )

            builder.createLogEvent(
                date: log.date,
                level: {
                    switch log.level {
                    case .debug: return .debug
                    case .info: return .info
                    case .notice: return .notice
                    case .warn: return .warn
                    case .error: return .error
                    case .critical: return .critical
                    }
                }(),
                message: log.message,
                error: log.error,
                errorFingerprint: nil,
                binaryImages: nil,
                attributes: .init(
                    userAttributes: log.userAttributes ?? [:],
                    internalAttributes: log.internalAttributes
                ),
                tags: [],
                context: context,
                threadName: log.thread,
                callback: writer.write
            )
        }

        return false
    }
}

/// Receiver to consume a Crash Log message as Log.
internal struct CrashLogReceiver: FeatureMessageReceiver {
    private struct Crash: Decodable {
        /// The crash report.
        let report: DDCrashReport
        /// The crash context
        let context: CrashContext
    }

    private struct CrashContext: Decodable {
        /// Interval between device and server time.
        let serverTimeOffset: TimeInterval
        /// The name of the service that data is generated from.
        let service: String
        /// The name of the environment that data is generated from.
        let env: String
        /// The version of the application that data is generated from.
        let version: String
        /// The build number of the application that data is generated from.
        let buildNumber: String
        /// Current device information.
        let device: DeviceInfo
        /// The version of Datadog iOS SDK.
        let sdkVersion: String
        /// Network information.
        ///
        /// Represents the current state of the device network connectivity and interface.
        /// The value can be `unknown` if the network interface is not available or if it has not
        /// yet been evaluated.
        let networkConnectionInfo: NetworkConnectionInfo?
        /// Carrier information.
        ///
        /// Represents the current telephony service info of the device.
        /// This value can be `nil` of no service is currently registered, or if the device does
        /// not support telephony services.
        let carrierInfo: CarrierInfo?
        /// Current user information.
        let userInfo: UserInfo?

        /// A type representing part of last RUM view information required to link crash log with previous RUM session.
        /// It mirrors the schema of `RUMViewEvent`, so we can decode it from the last `RUMViewEvent` coded in crash context.
        struct PartialRUMViewEvent: Decodable {
            struct Application: Decodable {
                let id: String
            }
            struct Session: Decodable {
                let id: String
            }
            struct View: Decodable {
                let id: String
            }

            let application: Application
            let session: Session
            let view: View
        }

        struct GlobalLogAttributes: Decodable {
            let attributes: [AttributeKey: AttributeValue]

            init(from decoder: Decoder) throws {
                // Decode other properties into [String: Codable] dictionary:
                let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
                self.attributes = try dynamicContainer.allKeys
                    .reduce(into: [:]) {
                        $0[$1.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: $1)
                    }
            }
        }

        /// The last RUM view in crashed app process.
        let lastRUMViewEvent: PartialRUMViewEvent?

        /// Last global log attributes
        let lastLogAttributes: GlobalLogAttributes?
    }

    /// Time provider.
    let dateProvider: DateProvider
    let logEventMapper: LogEventMapper?

    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        do {
            guard let crash: Crash = try message.baggage(forKey: LoggingMessageKeys.crash) else {
                return false
            }

            return send(report: crash.report, with: crash.context, to: core)
        } catch {
            core.telemetry
                .error("Failed to decode crash message in `LogMessageReceiver`", error: error)
        }
        return false
    }

    private func send(report: DDCrashReport, with crashContext: CrashContext, to core: DatadogCoreProtocol) -> Bool {
        // The `report.crashDate` uses system `Date` collected at the moment of crash, so we need to adjust it
        // to the server time before processing. Following use of the current correction is not ideal, but this is the best
        // approximation we can get.
        let date = (report.date ?? dateProvider.now)
            .addingTimeInterval(crashContext.serverTimeOffset)

        var errorAttributes: [AttributeKey: AttributeValue] = [:]

        // Set crash attributes for the error
        errorAttributes[DDError.threads] = report.threads
        errorAttributes[DDError.binaryImages] = report.binaryImages
        errorAttributes[DDError.meta] = report.meta
        errorAttributes[DDError.wasTruncated] = report.wasTruncated

        // Set RUM context if available (so emergency error is linked to the RUM session in Datadog app)
        errorAttributes[LogEvent.Attributes.RUM.applicationID] = crashContext.lastRUMViewEvent?.application.id
        errorAttributes[LogEvent.Attributes.RUM.sessionID] = crashContext.lastRUMViewEvent?.session.id
        errorAttributes[LogEvent.Attributes.RUM.viewID] = crashContext.lastRUMViewEvent?.view.id

        let user = crashContext.userInfo
        let deviceInfo = crashContext.device

        // Merge logs attributes with crash report attributes
        let lastLogAttributes = crashContext.lastLogAttributes?.attributes ?? [:]
        let additionalAttributes: [String: Encodable] = report.additionalAttributes.dd.decode() ?? [:]
        let userAttributes = lastLogAttributes.merging(additionalAttributes) { _, new in new }

        // crash reporting is considering the user consent from previous session, if an event reached
        // the message bus it means that consent was granted and we can safely bypass current consent.
        core.scope(for: LogsFeature.self).eventWriteContext(bypassConsent: true) { context, writer in
            let event = LogEvent(
                date: date,
                status: .emergency,
                message: report.message,
                error: .init(
                    kind: report.type,
                    message: report.message,
                    stack: report.stack,
                    sourceType: context.nativeSourceOverride ?? "ios"
                ),
                serviceName: crashContext.service,
                environment: crashContext.env,
                loggerName: "crash-reporter",
                loggerVersion: crashContext.sdkVersion,
                threadName: nil,
                applicationVersion: crashContext.version,
                applicationBuildNumber: crashContext.buildNumber,
                buildId: nil,
                variant: context.variant,
                dd: .init(
                    device: .init(
                        brand: deviceInfo.brand,
                        name: deviceInfo.name,
                        model: deviceInfo.model,
                        architecture: deviceInfo.architecture
                    )
                ),
                os: .init(
                    name: crashContext.device.osName,
                    version: crashContext.device.osVersion,
                    build: crashContext.device.osBuildNumber
                ),
                userInfo: .init(
                    id: user?.id,
                    name: user?.name,
                    email: user?.email,
                    extraInfo: user?.extraInfo ?? [:]
                ),
                networkConnectionInfo: crashContext.networkConnectionInfo,
                mobileCarrierInfo: crashContext.carrierInfo,
                attributes: .init(
                    userAttributes: userAttributes,
                    internalAttributes: errorAttributes
                ),
                tags: nil
            )

            logEventMapper?.map(event: event, callback: writer.write) ?? writer.write(value: event)
        }

        return true
    }
}

/// Receiver to consume a Log event coming from Browser SDK.
internal struct WebViewLogReceiver: FeatureMessageReceiver {
    /// Process messages receives from the bus.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case var .webview(.log(event)) = message else {
            return false
        }

        let versionKey = LogEventEncoder.StaticCodingKeys.applicationVersion.rawValue
        let envKey = LogEventEncoder.StaticCodingKeys.environment.rawValue
        let tagsKey = LogEventEncoder.StaticCodingKeys.tags.rawValue
        let dateKey = LogEventEncoder.StaticCodingKeys.date.rawValue

        core.scope(for: LogsFeature.self).eventWriteContext { context, writer in
            let ddTags = "\(versionKey):\(context.version),\(envKey):\(context.env)"

            if let tags = event[tagsKey] as? String, !tags.isEmpty {
                event[tagsKey] = "\(ddTags),\(tags)"
            } else {
                event[tagsKey] = ddTags
            }

            if let timestampInMs = event[dateKey] as? Int {
                let serverTimeOffsetInMs = context.serverTimeOffset.toInt64Milliseconds
                let correctedTimestamp = Int64(timestampInMs) + serverTimeOffsetInMs
                event[dateKey] = correctedTimestamp
            }

            if let rum = context.baggages[RUMContext.key] {
                do {
                    let rum = try rum.decode(type: RUMContext.self)
                    event[LogEvent.Attributes.RUM.applicationID] = rum.applicationID
                    event[LogEvent.Attributes.RUM.sessionID] = rum.sessionID
                    event[LogEvent.Attributes.RUM.viewID] = rum.viewID
                    event[LogEvent.Attributes.RUM.actionID] = rum.userActionID
                } catch {
                    core.telemetry.error("Fails to decode RUM context from Logs in `WebViewLogReceiver`", error: error)
                }
            }

            writer.write(value: AnyEncodable(event))
        }

        return true
    }
}
