/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation
import UIKit

// Test-only pacing. The control is enabled only after the preceding lifecycle is observed.
@MainActor final class PacedHostingInput {
    private let evidence = HostingSettings.evidence
    private var expectedID: String?
    private var consumedID: String?
    private var button: UIButton?

    private func key(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    func request(_ phase: String, title: String, controller: UIViewController,
                 attachments: [String: UIViewController], window: UIWindow,
                 issued: UInt64, deadline: UInt64) async throws {
        guard HostingSettings.mode == "manual", HostingSettings.identity["arm"] == "B",
              expectedID == nil, button == nil, controller.viewIfLoaded?.window === window,
              window.isKeyWindow, window.windowScene?.activationState == .foregroundActive,
              DispatchTime.now().uptimeNanoseconds < deadline
        else { throw HostingFailure.boundary("human-input-readiness") }
        let id = UUID().uuidString.lowercased()
        let snapshots = attachments.mapValues { item -> [String: Any] in
            ["controller": key(item), "loaded": item.isViewLoaded,
             "window": item.viewIfLoaded?.window.map(key) as Any? ?? NSNull()]
        }
        let control = UIButton(type: .system)
        control.setTitle(title, for: .normal)
        control.accessibilityIdentifier = "hosting." + phase
        control.backgroundColor = .secondarySystemBackground
        control.layer.cornerRadius = 8
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addAction(UIAction { [weak self, weak controller, weak window, weak control] _ in
            guard let self, let controller, let window, let control else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard self.expectedID == id, self.consumedID == nil, now < deadline,
                  control.isEnabled, control.window === window, controller.viewIfLoaded?.window === window,
                  window.isKeyWindow, window.windowScene?.activationState == .foregroundActive
            else {
                self.evidence.record("human-input-rejected", fields: ["request_id": id, "phase": phase])
                return
            }
            self.consumedID = id
            control.isEnabled = false
            self.evidence.record("human-input", fields: ["request_id": id, "phase": phase,
                "controller": self.key(controller), "window": self.key(window), "consumed_ns": now])
        }, for: .touchUpInside)
        controller.view.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            control.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            control.widthAnchor.constraint(equalToConstant: 240), control.heightAnchor.constraint(equalToConstant: 48)
        ])
        controller.view.layoutIfNeeded()
        button = control; expectedID = id; consumedID = nil
        evidence.record("human-ready", fields: ["request_id": id, "phase": phase,
            "title": title, "control": control.accessibilityIdentifier as Any,
            "controller": key(controller), "window": key(window), "attachments": snapshots,
            "issued_ns": issued, "deadline_ns": deadline])
        try await evidence.flush()
        defer {
            control.removeFromSuperview()
            button = nil; expectedID = nil; consumedID = nil
        }
        while consumedID != id {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw HostingFailure.boundary("human-input-" + phase) }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw HostingFailure.boundary("late-human-input") }
    }
}
