/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

private enum DDCFMessageID {
    static let setCustomTags: Int32 = 0x1111
    static let enableRUM: Int32 = 0x2222
    static let forceFlush: Int32 = 0x3333
}

internal class CITestIntegration {
    /// Current and active integration with CIApp.
    /// `nil` if the integration is not enabled.
    static let active: CITestIntegration? = CITestIntegration()

    /// CI context to be attached to RUM events that identifies that they were created in a CIApp test,
    let ciTestExecutionID: String
    /// RUMCITest model to be attached to events
    let rumCITest: RUMCITest
    /// Tag that must be added to spans and headers when running inside a CIApp test
    let origin = "ciapp-test"

    private init?(processInfo: ProcessInfo = .processInfo) {
        guard let testID = processInfo.environment["CI_VISIBILITY_TEST_EXECUTION_ID"] else {
            return nil
        }
        self.ciTestExecutionID = testID
        self.rumCITest = RUMCITest(testExecutionId: ciTestExecutionID)
    }

    /// Entry point for running all the tasks needed for CIApp integration
    func startIntegration() {
        startMessageListener()
        notifyRUMSession()
    }

    /// Notifies the CIApp framework that a RUM session is being started. It sends a message to a CFMessagePort that is
    /// created in the CIApp framework
    private func notifyRUMSession() {
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
    private func startMessageListener() {
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
