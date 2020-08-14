/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

@objcMembers
public class DDTracerConfiguration: NSObject {
    internal var swiftConfiguration = Tracer.Configuration()

    override public init() {}

    // MARK: - Public

    public func set(serviceName: String) {
        swiftConfiguration.serviceName = serviceName
    }

    public func sendNetworkInfo(_ enabled: Bool) {
        swiftConfiguration.sendNetworkInfo = enabled
    }
}
