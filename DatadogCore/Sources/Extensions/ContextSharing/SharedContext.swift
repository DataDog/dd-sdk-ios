/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// Objective-C compatible type that exposes selected properties from `DatadogContext` to Objective-C.
///
/// This class is intended for internal use, primarily by cross-platform libraries that need to access
/// Datadog context information from Objective-C code. Can be extended with other properties as long as
/// they are Objective-C compatible.
@objc(DDSharedContext)
@objcMembers
@_spi(Internal)
public class SharedContext: NSObject {
    public let userId: String?
    public let accountId: String?

    init(datadogContext: DatadogContext) {
        userId = datadogContext.userInfo?.id
        accountId = datadogContext.accountInfo?.id
    }
}
