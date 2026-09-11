/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Must match the private metadata written by `RemoteLogger`. This is an
/// in-process message-bus contract and is removed before creating the RUM event.
private let rumErrorTargetViewIDAttribute = "_dd.internal.rum.error.target_view_id"
private let rumErrorTargetActionIDAttribute = "_dd.internal.rum.error.target_action_id"
private let rumErrorTargetSceneIDAttribute = "_dd.internal.rum.error.target_scene_id"
private let rumErrorCapturedContextAttribute = "_dd.internal.rum.error.context_captured"

internal struct ErrorMessageReceiver: FeatureMessageReceiver {
    /// RUM feature scope.
    let featureScope: FeatureScope
    let monitor: Monitor

    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(error as RUMErrorMessage) = message else {
            return false
        }

        var attributes = error.attributes
        let hasCapturedContext = attributes.removeValue(forKey: rumErrorCapturedContextAttribute) as? Bool == true
        let capturedViewID = attributes.removeValue(forKey: rumErrorTargetViewIDAttribute) as? String
        let capturedSceneIdentifier = attributes.removeValue(forKey: rumErrorTargetSceneIDAttribute) as? String
        let target: RUMCommandTarget
        if let viewID = capturedViewID,
           let uuid = UUID(uuidString: viewID) {
            target = .view(RUMUUID(rawValue: uuid))
        } else if let sceneIdentifier = capturedSceneIdentifier,
                  !sceneIdentifier.isEmpty {
            target = .scene(RUMSceneIdentifier(rawValue: sceneIdentifier))
        } else if hasCapturedContext {
            target = .none
        } else {
            target = .processRepresentative
        }
        let capturedActionID = (attributes.removeValue(forKey: rumErrorTargetActionIDAttribute) as? String)
            .flatMap(UUID.init(uuidString:))
            .map(RUMUUID.init(rawValue:))
        let userActionTarget: RUMErrorUserActionTarget = hasCapturedContext
            ? .captured(capturedActionID)
            : .current

        monitor._internal?.addError(
            at: error.time,
            message: error.message,
            type: error.type,
            stack: error.stack,
            source: .init(rawValue: error.source) ?? .custom,
            globalAttributes: [:],
            attributes: attributes,
            binaryImages: error.binaryImages,
            target: target,
            userActionTarget: userActionTarget
        )

        return true
    }
}
