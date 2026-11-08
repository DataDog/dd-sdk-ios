/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {




    @MainActor
    func awaitOrdinaryBoundary(
        _ name: String, core: DatadogCore, condition: () -> Bool
    ) async throws {
        let watchdog = Date().addingTimeInterval(20)
        while Date() < watchdog {
            core.flush()
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Missing ordinary SwiftUI boundary: \(name)")
        throw OrdinarySwiftUIViewCaptureError.missingBoundary(name)
    }
}

enum OrdinarySwiftUIViewCaptureError: Error { case missingBoundary(String) }

private struct OrdinarySwiftUILifecycleObservation: Encodable {
    let sequence: Int
    let boundary: String
    let observation: RUMSwiftUIViewCallbackAdmission.LifecycleObservation
}

private final class OrdinarySwiftUIViewRows: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RUMViewEvent] = []
    func append(_ value: RUMViewEvent) { lock.lock(); defer { lock.unlock() }; values.append(value) }
    var views: [RUMViewEvent] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

@MainActor
final class OrdinarySwiftUIViewDriver: ObservableObject {
    @Published var visible = true
    var states: [Int] = []
    var disappearances = 0
    var update: (() -> Void)?
}

struct OrdinarySwiftUIViewChild: View {
    let driver: OrdinarySwiftUIViewDriver
    @State private var counter = 0
    var body: some View {
        Text("Counter \(counter)")
            .onAppear { driver.states.append(counter); driver.update = { counter += 1 } }
            .onChange(of: counter) { driver.states.append($0) }
            .onDisappear { driver.disappearances += 1 }
    }
}

private struct OrdinarySwiftUIViewRoot: View {
    let content: AnyView
    @ObservedObject var driver: OrdinarySwiftUIViewDriver
    var body: some View { if driver.visible { content } }
}
#endif
