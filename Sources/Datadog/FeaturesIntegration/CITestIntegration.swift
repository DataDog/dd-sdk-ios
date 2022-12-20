/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
    /// RUMCITest model to be attached to events, it contains the CI context
    let rumCITest: RUMCITest
    /// Tag that must be added to spans and headers when running inside a CIApp test
    let origin = "ciapp-test"

    private init?(processInfo: ProcessInfo = .processInfo) {
        guard let testID = processInfo.environment["CI_VISIBILITY_TEST_EXECUTION_ID"] else {
            return nil
        }
        self.rumCITest = RUMCITest(testExecutionId: testID)
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
        CFMessagePortSendRequest(
            remotePort,
            DDCFMessageID.enableRUM, // Message ID for notifying the test that rum is enabled
            nil,
            timeout,
            timeout,
            nil,
            nil
        )
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

        guard let port = CFMessagePortCreateLocal(nil, "DatadogRUMTestingPort" as CFString, attributeCallback, nil, nil) else {
            return
        }
        let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
    }
}
