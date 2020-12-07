/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// File writer which writes data to different folders depending on the tracking consent value.
internal class ConsentAwareDataWriter: FileWriterType {
    /// Queue used to synchronize reads and writes for the feature.
    /// TODO: RUMM-777 will be used synchronize `activeFileWriter` swaps on consent change.
    internal let queue: DispatchQueue
    /// File writer writting unauthorized data when consent is `.pending`.
    private let unauthorizedFileWriter: FileWriterType
    /// File writer writting authorized data when consent is `.granted`.
    private let authorizedFileWriter: FileWriterType

    /// File writer for current consent value (including `nil` if consent is `.notGranted`).
    private var activeFileWriter: FileWriterType?

    init(
        initialConsent: TrackingConsent,
        queue: DispatchQueue,
        unauthorizedFileWriter: FileWriterType,
        authorizedFileWriter: FileWriterType
    ) {
        self.queue = queue
        self.unauthorizedFileWriter = unauthorizedFileWriter
        self.authorizedFileWriter = authorizedFileWriter

        switch initialConsent {
        case .granted: self.activeFileWriter = authorizedFileWriter
        case .notGranted: self.activeFileWriter = nil
        case .pending: self.activeFileWriter = unauthorizedFileWriter
        }
    }

    func write<T>(value: T) where T: Encodable {
        activeFileWriter?.write(value: value)
    }
}
