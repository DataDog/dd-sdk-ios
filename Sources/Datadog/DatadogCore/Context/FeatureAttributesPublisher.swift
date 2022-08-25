/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Publishes current `FeatureMessageAttributes` to receiver.
internal final class FeatureAttributesPublisher: ContextValuePublisher {
    typealias Value = [String: FeatureMessageAttributes]

    let initialValue: Value = [:]

    private var receiver: ContextValueReceiver<Value>?

    /// The current attributes.
    ///
    /// Setting a new value will invoked the receiver for publication.
    var attributes: Value = [:] {
        didSet { receiver?(attributes) }
    }

    func publish(to receiver: @escaping ContextValueReceiver<Value>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}
