/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// This class exposes a subset of `DatadogContext` properties that can be represented in Objective-C.
/// This is done mainly to improve capabilities of cross-platform SDKs.
@_spi(objc)
public final class DDSharedContext: NSObject {
    /// Current user identifier set in the `UserInfo` object.
    public let userId: String?
    /// Current account identifier set in the `AccountInfo` object.
    public let accountId: String?

    public init(swiftContext context: DatadogContext) {
        self.userId = context.userInfo?.id
        self.accountId = context.accountInfo?.id
        super.init()
    }
}
