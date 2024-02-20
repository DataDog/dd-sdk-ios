/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Crash Report format supported by Datadog SDK.
@objc
public final class DDCrashReport: NSObject, Codable {
    /// Meta information about the process.
    /// Ref.: https://developer.apple.com/documentation/xcode/examining-the-fields-in-a-crash-report
    public struct Meta: Codable {
        /// A client-generated 16-byte UUID of the incident.
        public let incidentIdentifier: String?
        /// The name of the crashed process.
        public let process: String?
        /// Parent process information.
        public let parentProcess: String?
        /// The location of the executable on disk.
        public let path: String?
        /// The CPU architecture of the process that crashed.
        public let codeType: String?
        /// The name of the corresponding BSD termination signal.
        public let exceptionType: String?
        /// CPU specific information about the exception encoded into 64-bit hexadecimal number preceded by the signal code.
        public let exceptionCodes: String?

        public init(
            incidentIdentifier: String?,
            process: String?,
            parentProcess: String?,
            path: String?,
            codeType: String?,
            exceptionType: String?,
            exceptionCodes: String?
        ) {
            self.incidentIdentifier = incidentIdentifier
            self.process = process
            self.parentProcess = parentProcess
            self.path = path
            self.codeType = codeType
            self.exceptionType = exceptionType
            self.exceptionCodes = exceptionCodes
        }

        enum CodingKeys: String, CodingKey {
            case incidentIdentifier = "incident_identifier"
            case process = "process"
            case parentProcess = "parent_process"
            case path = "path"
            case codeType = "code_type"
            case exceptionType = "exception_type"
            case exceptionCodes = "exception_codes"
        }
    }

    /// The date of the crash occurrence.
    public let date: Date?
    /// Crash report type - used to group similar crash reports.
    /// In Datadog Error Tracking this corresponds to `error.type`.
    public let type: String
    /// Crash report message - if possible, it should provide additional troubleshooting information in addition to the crash type.
    /// In Datadog Error Tracking this corresponds to `error.message`.
    public let message: String
    /// Unsymbolicated stack trace related to the crash (this can be either uncaugh exception backtrace or stack trace of the halted thread).
    /// In Datadog Error Tracking this corresponds to `error.stack`.
    public let stack: String
    /// All threads running in the process.
    public let threads: [DDThread]
    /// List of binary images referenced from all stack traces.
    public let binaryImages: [BinaryImage]
    /// Meta information about the crash and process.
    public let meta: Meta
    /// If any stack trace information in `threads` was truncated due to stack trace minimization.
    public let wasTruncated: Bool
    /// The last context injected through `inject(context:)`
    public let context: Data?

    public init(
        date: Date?,
        type: String,
        message: String,
        stack: String,
        threads: [DDThread],
        binaryImages: [BinaryImage],
        meta: Meta,
        wasTruncated: Bool,
        context: Data?
    ) {
        self.date = date
        self.type = type
        self.message = message
        self.stack = stack
        self.threads = threads
        self.binaryImages = binaryImages
        self.meta = meta
        self.wasTruncated = wasTruncated
        self.context = context
    }
}
