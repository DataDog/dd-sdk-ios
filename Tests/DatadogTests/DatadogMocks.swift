import Foundation
@testable import Datadog

/*
A collection of mock configurations for SDK.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension LogsUploader {
    /// Mocks `LogsUploader` instance which notifies sent requests on `captureBlock`.
    static func mockUploaderCapturingRequests(captureBlock: @escaping (URLRequest) -> Void) -> LogsUploader {
        return LogsUploader(
            validURL: .mockAny(),
            httpClient: .mockRequestCapture(captureBlock: captureBlock)
        )
    }
}
