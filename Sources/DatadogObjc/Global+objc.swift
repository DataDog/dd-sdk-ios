/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogTrace
import DatadogRUM

@objc
public class DDGlobal: NSObject {
    @objc public static var sharedTracer: DatadogObjc.DDTracer { .init(swiftTracer: DatadogTracer.shared()) }
}
