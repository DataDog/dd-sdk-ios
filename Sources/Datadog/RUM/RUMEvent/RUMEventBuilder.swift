/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct RUMEventBuilder {
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider
    /// Shared network connection info provider (or `nil` if disabled for given `RUMMonitor`).
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType?
    /// Shared mobile carrier info provider (or `nil` if disabled for given `RUMMonitor`).
    let carrierInfoProvider: CarrierInfoProviderType?

    func createRUMEvent<DM: RUMDataModel>(with model: DM, attributes: [String: Encodable]?) -> RUMEvent<DM> {
        return RUMEvent(
            model: model,
            userInfo: userInfoProvider.value,
            networkConnectionInfo: networkConnectionInfoProvider?.current,
            mobileCarrierInfo: carrierInfoProvider?.current,
            attributes: attributes
        )
    }
}
