/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

private enum DDCFMessageID {
    static let customTags: Int32 = 0x1111
    static let enableRUM: Int32 = 0x2222
    static let forceFlush: Int32 = 0x3333
}

internal enum CITestIntegration {
    /// CI context to be attached to RUM events that identifies it was started by a CI test,
    static var ciTestExecutionID: String? {
        return ProcessInfo.processInfo.environment["CI_VISIBILITY_TEST_EXECUTION_ID"]
    }

    /// Convinence function to check if RUM was started in a CIApp test
    static func isEnabled() -> Bool {
        return ciTestExecutionID != nil
    }

    /// Origin value that must be set to Spans and headers to indicate that the trace was initiated by a CIApp test
    static var origin: String? {
        if isEnabled() {
            return "ciapp-test"
        }
        return nil
    }

    /// Entry point for running all the tasks needed for CIApp integration
    static func startIntegration() {
        startMessageListener()
        notifyRUMSession()
    }

    /// Notifies the CIApp framework that a RUM session is being started. It sends a message to a CFMessagePort that is
    /// created in the CIApp framework
    private static func notifyRUMSession() {
        let timeout: CFTimeInterval = 1.0
        guard let remotePort = CFMessagePortCreateRemote(nil, "DatadogTestingPort" as CFString) else {
            return
        }
        let status = CFMessagePortSendRequest(
            remotePort,
            DDCFMessageID.enableRUM, // Message ID for notifying the test that rum is enabled
            nil,
            timeout,
            timeout,
            nil,
            nil
        )
        if status == kCFMessagePortSuccess {
        } else {}
    }

    /// Creates a CFMessagePort that is used by the CIApp framework to notify that a test is going to finish, so all
    /// information must be flushed to the backend. It uses a non public API `internalFlushAndDeinitialize()`
    private static func startMessageListener() {
        func attributeCallback(port: CFMessagePort?, msgid: Int32, data: CFData?, info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
            switch msgid {
            case DDCFMessageID.forceFlush:
                    Datadog.internalFlushAndDeinitialize()
            default:
                break
            }
            return nil
        }

        let port = CFMessagePortCreateLocal(nil, "DatadogRUMTestingPort" as CFString, attributeCallback, nil, nil)
        if port == nil {
            print("DatadogTestingPort CFMessagePortCreateLocal failed")
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
    }
}
