/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Publisher generating RUM Commands on `SwiftUI.View` events.
internal protocol SwiftUIViewHandler: RUMCommandPublisher {
    /// Respond to a `SwiftUI.View.onAppear` event.
    func notify_onAppear(identity: String, name: String, path: String, attributes: [AttributeKey: AttributeValue])

    /// Respond to a `SwiftUI.View.onDisappear` event.
    func notify_onDisappear(identity: String)

    /// Replace one materialized SwiftUI navigation occurrence without exposing
    /// the underlying view in the handler's navigation stack.
    func notify_replaceOccurrence(
        oldIdentity: String,
        newIdentity: String,
        name: String,
        path: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier?
    )
}
