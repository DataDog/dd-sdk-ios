/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Establishes a communications channel from UITests runner to the app under tests (allows sending messages
/// from `DatadogIntegrationTests` to `Example` app).
///
/// Ref.: https://developer.apple.com/documentation/corefoundation/cfmessageport-rs2
///
/// Note: this class is used by two targets: `DatadogIntegrationTests` (sender) and `Example` (receiver).
internal class MessagePortChannel {
    private static let portName = "DDExampleAppPort" as CFString

    enum Message: Int32 {
        case endRUMSession = 0x1111
    }

    struct ChannelError: Error, CustomStringConvertible {
        let description: String
    }

    static func createSender() throws -> Sender {
        return try Sender()
    }

    static func createReceiver() throws -> Receiver {
        return try Receiver()
    }

    // MARK: - Sending messages

    /// Sender, obtained in `UITests` runner process. Sends messages to `MessagePortChannel.portName`.
    internal class Sender {
        private let remotePort: CFMessagePort

        fileprivate init() throws {
            guard let remotePort = CFMessagePortCreateRemote(nil, MessagePortChannel.portName) else {
                throw ChannelError(description: "⚠️ `MessagePortChannel.Sender` - failed to instantiate remote port")
            }
            self.remotePort = remotePort
        }

        func send(message: Message) throws {
            let timeout: CFTimeInterval = 5.0
            let replyMode = CFRunLoopMode.defaultMode.rawValue // use `default` mode to avaid delivery confirmation
            let deliveryStatus = CFMessagePortSendRequest(remotePort, message.rawValue, nil, timeout, timeout, replyMode, nil)
            if deliveryStatus != kCFMessagePortSuccess {
                throw ChannelError(description: "⚠️ `MessagePortChannel.Sender` - failed to send '\(message)' message")
            }
        }
    }

    // MARK: - Receiving messages

    /// Receiver, obtained in `Example` app process. Receives messages on `MessagePortChannel.portName`.
    internal class Receiver {
        private let localPort: CFMessagePort
        private static var currentListener: ((Message) -> Void)?

        fileprivate init() throws {
            func callback(port: CFMessagePort?, msgid: Int32, data: CFData?, info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
                if let message = Message(rawValue: msgid) {
                    Receiver.currentListener?(message)
                } else {
                    print("⚠️ `MessagePortChannel.Receiver` - failed to read message from `msgid`: \(msgid)")
                }
                return nil
            }

            guard let localPort = CFMessagePortCreateLocal(nil, MessagePortChannel.portName, callback, nil, nil) else {
                throw ChannelError(description: "⚠️ `MessagePortChannel.Receiver` - failed to instantiate local port")
            }
            self.localPort = localPort
        }

        func startListening(_ listener: @escaping (Message) -> Void) {
            precondition(Receiver.currentListener == nil, "Listener was already started")
            Receiver.currentListener = listener
            let runLoopSource = CFMessagePortCreateRunLoopSource(nil, localPort, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        }
    }
}
