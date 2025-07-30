/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/* Collection of mappings from various types to `RUMDataModel` format. */

extension BinaryInteger {
    var toInt64: Int64 {
        return Int64(clamping: self)
    }
}

internal extension RUMUUID {
    var toRUMDataFormat: String {
        return rawValue.uuidString.lowercased()
    }
}

internal extension RUMInternalErrorSource {
    var toRUMDataFormat: RUMErrorEvent.Error.Source {
        switch self {
        case .custom: return .custom
        case .source: return .source
        case .network: return .network
        case .webview: return .webview
        case .console: return .console
        case .logger: return .logger
        }
    }
}

internal extension RUMActionType {
    var toRUMDataFormat: RUMActionEvent.Action.ActionType {
        switch self {
        case .tap: return .tap
        case .click: return .click
        case .scroll: return .scroll
        case .swipe: return .swipe
        case .custom: return .custom
        }
    }
}

internal extension RUMViewEvent.Source {
    var toErrorEventSource: RUMErrorEvent.Source {
        switch self {
        case .ios: return .ios
        case .android: return .android
        case .browser: return .browser
        case .reactNative: return .reactNative
        case .flutter: return .flutter
        case .roku: return .roku
        case .unity: return .unity
        case .kotlinMultiplatform: return .kotlinMultiplatform
        }
    }
}

internal extension RUMViewEvent {
    /// Metadata associated with the `RUMViewEvent`.
    /// It may be used to filter out the `RUMViewEvent` from the batch.
    struct Metadata: Codable {
        let id: String
        let documentVersion: Int64
        let hasAccessibility: Bool
        /// Duration of the view in nanoseconds.
        let duration: Int64?
        /// Index of the view within its session (0 for the first view).
        let indexInSession: Int?

        private enum CodingKeys: String, CodingKey {
            case id = "id"
            case documentVersion = "document_version"
            case hasAccessibility = "has_accessibility"
            case duration = "duration"
            case indexInSession = "index"
        }

        init(id: String, documentVersion: Int64, hasAccessibility: Bool = false) {
            self.id = id
            self.documentVersion = documentVersion
            self.hasAccessibility = hasAccessibility ?? false
        }
    }

    enum EventType: String, Codable {
        case view
    }

    /// Checks if the accessibility object has any meaningful data
    private func hasValidAccessibilityData() -> Bool {
        guard let accessibility = view.accessibility else {
            return false
        }

        // Check if any accessibility property has a non-nil value
        return accessibility.assistiveSwitchEnabled != nil ||
               accessibility.assistiveTouchEnabled != nil ||
               accessibility.boldTextEnabled != nil ||
               accessibility.buttonShapesEnabled != nil ||
               accessibility.closedCaptioningEnabled != nil ||
               accessibility.grayscaleEnabled != nil ||
               accessibility.increaseContrastEnabled != nil ||
               accessibility.invertColorsEnabled != nil ||
               accessibility.monoAudioEnabled != nil ||
               accessibility.onOffSwitchLabelsEnabled != nil ||
               accessibility.reduceMotionEnabled != nil ||
               accessibility.reduceTransparencyEnabled != nil ||
               accessibility.reducedAnimationsEnabled != nil ||
               accessibility.rtlEnabled != nil ||
               accessibility.screenReaderEnabled != nil ||
               accessibility.shakeToUndoEnabled != nil ||
               accessibility.shouldDifferentiateWithoutColor != nil ||
               accessibility.singleAppModeEnabled != nil ||
               accessibility.speakScreenEnabled != nil ||
               accessibility.speakSelectionEnabled != nil ||
               accessibility.textSize != nil ||
               accessibility.videoAutoplayEnabled != nil
    }

    /// Creates `Metadata` from the given `RUMViewEvent`.
    /// - Returns: The `Metadata` for the given `RUMViewEvent`.
    func metadata(viewIndexInSession: Int) -> Metadata {
        return Metadata(
            id: view.id,
            documentVersion: dd.documentVersion,
            hasAccessibility: hasValidAccessibilityData(),
            duration: view.timeSpent,
            indexInSession: viewIndexInSession
        )
    }
}

internal extension DDThread {
    var toRUMDataFormat: RUMErrorEvent.Error.Threads {
        return .init(
            crashed: crashed,
            name: name,
            stack: stack,
            state: nil
        )
    }
}

internal extension Array where Element == DDThread {
    var toRUMDataFormat: [RUMErrorEvent.Error.Threads] { map { $0.toRUMDataFormat } }
}

internal extension BinaryImage {
    var toRUMDataFormat: RUMErrorEvent.Error.BinaryImages {
        return .init(
            arch: architecture,
            isSystem: isSystemLibrary,
            loadAddress: loadAddress,
            maxAddress: maxAddress,
            name: libraryName,
            uuid: uuid
        )
    }
}

internal extension Array where Element == BinaryImage {
    var toRUMDataFormat: [RUMErrorEvent.Error.BinaryImages] { map { $0.toRUMDataFormat } }
}

internal extension DDCrashReport.Meta {
    var toRUMDataFormat: RUMErrorEvent.Error.Meta {
        return .init(
            codeType: codeType,
            exceptionCodes: exceptionCodes,
            exceptionType: exceptionType,
            incidentIdentifier: incidentIdentifier,
            parentProcess: parentProcess,
            path: path,
            process: process
        )
    }
}
