/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2016-Present Datadog, Inc.
 */

import Foundation

/**
 A configuration object to initialize Datadog's features.
 - Parameters:
     - clientToken: A valid Datadog client token.
     - env: The application’s environment, for example: prod, pre-prod, staging, etc.
     - applicationId: The RUM application ID.
 */
@objc(DdSdkConfiguration)
public class DdSdkConfiguration: NSObject{
    public var clientToken: NSString = ""
    public var env: NSString = ""
    public var applicationId: NSString? = nil

    public init(
        clientToken: NSString,
        env: NSString,
        applicationId: NSString?
    ) {
        self.clientToken = clientToken
        self.env = env
        self.applicationId = applicationId
    }
}
