/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

extension SessionReplayConfiguration: AnyMockable, RandomMockable {
    static func mockAny() -> SessionReplayConfiguration {
        return .mockWith()
    }

    static func mockRandom() -> SessionReplayConfiguration {
        return SessionReplayConfiguration(
            privacy: .mockRandom(),
            customUploadURL: .mockRandom()
        )
    }

    static func mockWith(
        privacy: SessionReplayPrivacy = .mockAny(),
        customUploadURL: URL? = .mockAny()
    ) -> SessionReplayConfiguration {
        return SessionReplayConfiguration(
            privacy: privacy,
            customUploadURL: customUploadURL
        )
    }
}

extension SessionReplayPrivacy: AnyMockable, RandomMockable {
    static func mockAny() -> SessionReplayPrivacy {
        return .allowAll
    }

    static func mockRandom() -> SessionReplayPrivacy {
        return [
            .allowAll,
            .maskAll
        ].randomElement()!
    }
}
