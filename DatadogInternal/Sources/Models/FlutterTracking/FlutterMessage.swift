/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A Flutter message is transmitted by the `DatadogSessionReplay` Flutter plugin
/// on the message-bus when Flutter is embedded inside a native iOS app.
///
/// Such message carries session-replay records captured by the Flutter engine and
/// is handled by `FlutterRecordReceiver` inside `SessionReplayFeature`.
public enum FlutterMessage {
    /// Raw record dictionary — one entry per SR record (meta, focus, snapshot, …).
    public typealias Records = [[String: Any]]

    /// A set of Flutter session-replay records for the given RUM view.
    ///
    /// - Parameters:
    ///   - records: The SR records captured by the Flutter engine.
    ///   - viewID: The RUM view ID reported by the Flutter RUM module.
    case record(Records, String)
}
