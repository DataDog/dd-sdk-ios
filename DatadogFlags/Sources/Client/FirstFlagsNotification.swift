/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Construction and installation are independent gates. No application code runs under this lock.
internal final class FirstFlagsNotification {
    typealias Callback = (FlagsClientProtocol, FlagsClientEvent, FlagsData) throws -> Void
    private let lock = NSLock()
    private var callback: Callback?
    private weak var client: FlagsClientProtocol?
    private var event: FlagsClientEvent?
    private var snapshot: FlagsData?
    private var installationIsVisible = false
    private var scheduled = false
    private let schedule: (@escaping () -> Void) -> Void

    init(callback: @escaping Callback, schedule: @escaping (@escaping () -> Void) -> Void = {
        DispatchQueue.global(qos: .userInitiated).async(execute: $0)
    }) {
        self.callback = callback
        self.schedule = schedule
    }

    /// Called under the repository installation lock, before another installation can win.
    @discardableResult
    func claim(data: FlagsData) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard event == nil else {
            return false
        }
        snapshot = data
        event = FlagsClientEvent(
            type: .configurationChanged,
            providerName: "Datadog",
            flagsChanged: Array(data.flags.keys).sorted(),
            message: nil,
            errorCode: nil,
            metadata: [:]
        )
        return true
    }

    /// Called only after releasing repository locks and disk waiters.
    func installed() {
        lock.lock()
        installationIsVisible = event != nil
        lock.unlock()
        scheduleIfReady()
    }

    /// Called after the complete public client has been registered.
    func activate(client: FlagsClientProtocol) {
        lock.lock()
        self.client = client
        lock.unlock()
        scheduleIfReady()
    }

    private func scheduleIfReady() {
        lock.lock()
        guard !scheduled, installationIsVisible, event != nil, client != nil else {
            lock.unlock()
            return
        }
        scheduled = true
        lock.unlock()
        schedule { [weak self] in self?.deliver() }
    }

    private func deliver() {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        let client = self.client
        let event = self.event
        let snapshot = self.snapshot
        self.snapshot = nil
        lock.unlock()
        guard let callback, let client, let event, let snapshot else {
            return
        }
        do {
            try callback(client, event, snapshot)
        } catch {
            // Do not log the application error, which can contain customer data.
            DD.logger.warn("The onFirstFlags callback threw an error.")
        }
    }
}
