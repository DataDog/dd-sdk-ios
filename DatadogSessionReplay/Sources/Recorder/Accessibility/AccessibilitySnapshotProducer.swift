/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal struct AccessibilitySnapshot {
    let voiceOverWireframes: [NodeWireframesBuilder]
    let notificationWireframes: [NodeWireframesBuilder]
}

internal class AccessibilitySnapshotProducer {
    fileprivate struct VoiceOverFocusNode {
        let ids: (WireframeID, WireframeID)
        let accessibilityFrame: CGRect
        let accessibilityLabel: String?
    }

    fileprivate struct VoiceOverStatusNode {
        let ids: (WireframeID, WireframeID)
        let frame: CGRect
    }

    fileprivate struct NotificationNode {
        let id: WireframeID
        let frame: CGRect
        let title: String
        let creationTime: Date
    }

    private let ids: NodeIDGenerator
    private let windowObserver: AppWindowObserver
    private let textObfuscator = TextObfuscator()

    private var voiceOverStatusNode: VoiceOverStatusNode? = nil
    private var voiceOverFocusNode: VoiceOverFocusNode? = nil
    private var notificationNode: NotificationNode? = nil

    init(idsGenerator: NodeIDGenerator, windowObserver: AppWindowObserver) {
        self.ids = idsGenerator
        self.windowObserver = windowObserver

        NotificationCenter.default.addObserver(
            forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main) { [weak self] notification in
                let element = notification.userInfo?[UIAccessibility.focusedElementUserInfoKey]
                self?.voiceOverFocusChanged(to: element)
            }

        NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
                if UIAccessibility.isVoiceOverRunning == false {
                    self?.voiceOverFocusNode = nil
                    self?.voiceOverStatusNode = nil
                }
            }

        NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] notification in
                guard let newValue = notification.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? UIContentSizeCategory else {
                    return
                }
                if #available(iOS 16.0, *) {
                    var name = newValue.rawValue
                    if name.hasPrefix("UICTContentSizeCategoryAccessibility") {
                        name.trimPrefix("UICTContentSizeCategoryAccessibility")
                        name = "AX-" + name
                    } else {
                        name.trimPrefix("UICTContentSizeCategory")
                    }
                    self?.createNotification(title: "Content size changed: \(name)")
                }
            }
    }

    func takeSnapshot(context: Recorder.Context) -> AccessibilitySnapshot? {
        let trackVoiceOver = context.accessibilityOptions.contains(.trackVoiceOverFocus)
        let trackSettings = context.accessibilityOptions.contains(.notifyAccessibilitySettings)

        return AccessibilitySnapshot(
            voiceOverWireframes: trackVoiceOver ? getVoiceOverWireframes(context: context) : [],
            notificationWireframes: trackSettings ? getNotificationWireframes(context: context) : []
        )
    }

    private func getVoiceOverWireframes(context: Recorder.Context) -> [NodeWireframesBuilder] {
        guard let focusNode = voiceOverFocusNode, let statusNode = voiceOverStatusNode else {
            return []
        }

        return [
            VoiceOverStatusWireframesBuilder(
                ids: statusNode.ids,
                wireframeRect: statusNode.frame
            ),
            VoiceOverFocusWireframesBuilder(
                ids: focusNode.ids,
                wireframeRect: focusNode.accessibilityFrame,
                accessibilityLabel: focusNode.accessibilityLabel,
                textObfuscator: context.privacy == .maskAll ? textObfuscator : nopTextObfuscator
            )
        ]
    }

    private func createNotification(title: String) {
        guard let window = windowObserver.relevantWindow else {
            return
        }

        guard notificationNode?.title != title else {
            return
        }

        notificationNode = NotificationNode(
            id: ids.getNextID(),
            frame: CGRect(origin: .zero, size: CGSize(width: window.frame.width * 0.75, height: 64))
                .putInside(window.frame, horizontalAlignment: .center, verticalAlignment: .middle),
            title: title,
            creationTime: Date()
        )
    }

    private func getNotificationWireframes(context: Recorder.Context) -> [NodeWireframesBuilder] {
        guard let node = notificationNode else {
            return []
        }

        let stillTime: TimeInterval = 1
        let animationTime: TimeInterval = 0.5
        let currentLifetime = Date(timeIntervalSinceNow: -stillTime).timeIntervalSince(node.creationTime)
        let percentage = currentLifetime / animationTime
        let opacity = min(0.9, CGFloat(1 - percentage))

        if percentage > 1 {
            notificationNode = nil
            return []
        }

        return [
            AccessibilityNotificationWireframesBuilder(
                wireframeID: node.id,
                wireframeRect: node.frame,
                text: node.title,
                opacity: opacity
            )
        ]
    }

    // MARK: - Notification handling

    private func voiceOverFocusChanged(to element: Any?) {
        // Ref.:
        // > Instances of this class (`UIAccessibilityElement`) can be used as "fake" accessibility elements.
        // > An accessibility container (see UIAccessibility.h) can create and vend instances
        // > of UIAccessibilityElement to cover for user interface items that are not
        // > backed by a UIView (for example: painted text or icon).
        if let accessibilityElement = element as? UIAccessibilityElement {
            voiceOverFocusNode = VoiceOverFocusNode(
                ids: (ids.getNextID(), ids.getNextID()),
                accessibilityFrame: accessibilityElement.accessibilityFrame,
                accessibilityLabel: accessibilityElement.accessibilityLabel
            )
        } else if let view = element as? UIView {
            voiceOverFocusNode = VoiceOverFocusNode(
                ids: (ids.getNextID(), ids.getNextID()),
                accessibilityFrame: view.accessibilityFrame,
                accessibilityLabel: view.accessibilityLabel
            )
        } else if let object = element as? NSObject { // the case of `SwiftUI.AccessibilityNode`
            voiceOverFocusNode = VoiceOverFocusNode(
                ids: (ids.getNextID(), ids.getNextID()),
                accessibilityFrame: object.accessibilityFrame,
                accessibilityLabel: object.accessibilityLabel
            )
        } else {
            voiceOverFocusNode = nil
        }

        if element != nil, let window = windowObserver.relevantWindow {
            voiceOverStatusNode = VoiceOverStatusNode(
                ids: (ids.getNextID(), ids.getNextID()),
                frame: window.frame
            )
        } else {
            voiceOverStatusNode = nil
        }
    }
}

internal struct VoiceOverFocusWireframesBuilder: NodeWireframesBuilder {
    let ids: (WireframeID, WireframeID)
    var wireframeID: WireframeID { ids.0 }
    let wireframeRect: CGRect
    let accessibilityLabel: String?
    let textObfuscator: TextObfuscating

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let text = accessibilityLabel.map { "\"\($0)\"" }

        return builder.createAccessibilityWireframes(
            ids: (ids.0, ids.1),
            frame: wireframeRect,
            color: accessibilityLabel != nil ? .black : .red,
            annotationText: text.map(textObfuscator.mask(text:)) ?? "<MISSING>",
            borderWidth: 3,
            cornerRadius: 0
        )
    }
}

internal struct VoiceOverStatusWireframesBuilder: NodeWireframesBuilder {
    let ids: (WireframeID, WireframeID)
    var wireframeID: WireframeID { ids.0 }
    let wireframeRect: CGRect

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        let border = builder.createShapeWireframe(
            id: ids.0,
            frame: wireframeRect,
            borderColor: datadogColor,
            borderWidth: 4
        )

        let text = NSString(string: "Voice Over ENABLED")
        let font = UIFont.systemFont(ofSize: 16)
        let textSize = text.size(withAttributes: [.font: font])
        let textFrame = CGRect(origin: .zero, size: textSize)
            .putInside(wireframeRect, horizontalAlignment: .center, verticalAlignment: .bottom)

        let label = builder.createTextWireframe(
            id: ids.1,
            frame: textFrame,
            text: text as String,
            textFrame: textFrame,
            textAlignment: .init(horizontal: .center, vertical: .center),
            textColor: UIColor.white.cgColor,
            backgroundColor: datadogColor
        )

        return [border, label]
    }
}

internal struct AccessibilityNotificationWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    let wireframeRect: CGRect
    let text: String
    let opacity: CGFloat

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createTextWireframe(
                id: wireframeID,
                frame: wireframeRect,
                text: text,
                textFrame: wireframeRect,
                textAlignment: .init(horizontal: .center, vertical: .center),
                textColor: UIColor.white.cgColor,
                font: .systemFont(ofSize: 16),
                backgroundColor: datadogColor,
                cornerRadius: 15,
                opacity: opacity
            )
        ]
    }
}

private let datadogColor = UIColor(red: 99/256, green: 44/256, blue: 166/256, alpha: 1).cgColor
