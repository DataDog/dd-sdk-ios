/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

internal class CarrierInfoPublisherMock: ContextValuePublisher, ContextValueReader {
    let initialValue: CarrierInfo?

    var carrierInfo: CarrierInfo? {
        didSet { receiver?(carrierInfo) }
    }

    private var receiver: ContextValueReceiver<CarrierInfo?>?

    init(value: CarrierInfo? = nil) {
        initialValue = value
        carrierInfo = value
    }

    func read(_ receiver: (CarrierInfo?) -> Void) {
        receiver(carrierInfo)
    }

    func publish(to receiver: @escaping ContextValueReceiver<CarrierInfo?>) {
        self.receiver = receiver
    }

    func cancel() {
        receiver = nil
    }
}

extension AnyCarrierInfoPublisher: AnyMockable {
    static func mockAny() -> AnyCarrierInfoPublisher {
        .init(CarrierInfoPublisherMock())
    }
}
