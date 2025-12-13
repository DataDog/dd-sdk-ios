/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal final class ContextSharingFeature: DatadogFeature {
    static var name: String = "_extension_context_sharing"

    var messageReceiver: FeatureMessageReceiver

    init(messageReceiver: FeatureMessageReceiver) {
        self.messageReceiver = messageReceiver
    }
}
