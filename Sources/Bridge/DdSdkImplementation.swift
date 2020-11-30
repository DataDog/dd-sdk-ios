//
//  DdSdkImplementation.swift
//  DatadogSDK
//
//  Created by Xavier Gouchet on 30/11/2020.
//

import Foundation

class DdSdkImplementation: DdSdk {
    func initialize(configuration: DdSdkConfiguration) {
//        let config = Datadog.Configuration(rumApplicationID: configuration.applicationId as String?, clientToken: configuration.clientToken as String, environment: configuration.env as String, loggingEnabled: true, tracingEnabled: true, rumEnabled: true, logsEndpoint: .us, tracesEndpoint: .us, rumEndpoint: .us, rumSessionsSamplingRate: 100.0, rumUIKitActionsTrackingEnabled: false)
//        Datadog.initialize(appContext: AppContext(), configuration: config)
        print("DdSdkImplementation.initialize")
    }
}
