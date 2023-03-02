/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Crash Report format supported by Datadog SDK.
@objc
public class DDCrashReport: NSObject, Codable {
    public struct Thread: Codable {
        /// The name of the thread, e.g. `"Thread 0"`
        internal let name: String
        /// Unsymbolicated stack trace of the crash.
        internal let stack: String
        /// If the thread was halted.
        internal let crashed: Bool
        /// Thread state (CPU registers dump), only available for halted thread.
        internal let state: String?

        public init(
            name: String,
            stack: String,
            crashed: Bool,
            state: String?
        ) {
            self.name = name
            self.stack = stack
            self.crashed = crashed
            self.state = state
        }

        // MARK: - Encoding

        enum CodingKeys: String, CodingKey {
            case name = "name"
            case stack = "stack"
            case crashed = "crashed"
            case state = "state"
        }
    }

    public struct BinaryImage: Codable {
        internal let libraryName: String
        internal let uuid: String
        internal let architecture: String
        internal let isSystemLibrary: Bool
        internal let loadAddress: String
        internal let maxAddress: String

        public init(
            libraryName: String,
            uuid: String,
            architecture: String,
            isSystemLibrary: Bool,
            loadAddress: String,
            maxAddress: String
        ) {
            self.libraryName = libraryName
            self.uuid = uuid
            self.architecture = architecture
            self.isSystemLibrary = isSystemLibrary
            self.loadAddress = loadAddress
            self.maxAddress = maxAddress
        }

        // MARK: - Encoding

        enum CodingKeys: String, CodingKey {
            case libraryName = "name"
            case uuid = "uuid"
            case architecture = "arch"
            case isSystemLibrary = "is_system"
            case loadAddress = "load_address"
            case maxAddress = "max_address"
        }
    }

    /// Meta information about the process.
    /// Ref.: https://developer.apple.com/documentation/xcode/examining-the-fields-in-a-crash-report
    public struct Meta: Codable {
        /// A client-generated 16-byte UUID of the incident.
        internal let incidentIdentifier: String?
        /// The name of the crashed process.
        internal let processName: String?
        /// Parent process information.
        internal let parentProcess: String?
        /// The location of the executable on disk.
        internal let path: String?
        /// The CPU architecture of the process that crashed.
        internal let codeType: String?
        /// The name of the corresponding BSD termination signal.
        internal let exceptionType: String?
        /// CPU specific information about the exception encoded into 64-bit hexadecimal number preceded by the signal code.
        internal let exceptionCodes: String?

        public init(
            incidentIdentifier: String?,
            processName: String?,
            parentProcess: String?,
            path: String?,
            codeType: String?,
            exceptionType: String?,
            exceptionCodes: String?
        ) {
            self.incidentIdentifier = incidentIdentifier
            self.processName = processName
            self.parentProcess = parentProcess
            self.path = path
            self.codeType = codeType
            self.exceptionType = exceptionType
            self.exceptionCodes = exceptionCodes
        }

        enum CodingKeys: String, CodingKey {
            case incidentIdentifier = "incident_identifier"
            case processName = "process"
            case parentProcess = "parent_process"
            case path = "path"
            case codeType = "code_type"
            case exceptionType = "exception_type"
            case exceptionCodes = "exception_codes"
        }
    }

    /// The date of the crash occurrence.
    internal let date: Date?
    /// Crash report type - used to group similar crash reports.
    /// In Datadog Error Tracking this corresponds to `error.type`.
    internal let type: String
    /// Crash report message - if possible, it should provide additional troubleshooting information in addition to the crash type.
    /// In Datadog Error Tracking this corresponds to `error.message`.
    internal let message: String
    /// Unsymbolicated stack trace related to the crash (this can be either uncaugh exception backtrace or stack trace of the halted thread).
    /// In Datadog Error Tracking this corresponds to `error.stack`.
    internal let stack: String
    /// All threads running in the process.
    internal let threads: [Thread]
    /// List of binary images referenced from all stack traces.
    internal let binaryImages: [BinaryImage]
    /// Meta information about the crash and process.
    internal let meta: Meta
    /// If any stack trace information was truncated due to crash report minimization.
    internal let wasTruncated: Bool
    /// The last context injected through `inject(context:)`
    internal let context: Data?

    public init(
        date: Date?,
        type: String,
        message: String,
        stack: String,
        threads: [Thread],
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

/// An interface for enabling crash reporting feature in Datadog SDK.
/// It is implemented by `DDCrashReportingPlugin` from `DatadogCrashReporting` framework.
///
/// The SDK calls each API on a background thread and succeeding calls are synchronized.
@objc
public protocol DDCrashReportingPluginType: AnyObject {
    /// Reads unprocessed crash report if available.
    /// - Parameter completion: the completion block called with the value of `DDCrashReport` if a crash report is available
    /// or with `nil` otherwise. The value returned by the receiver should indicate if the crash report was processed correctly (`true`)
    /// or something went wrong (`false)`. Depending on the returned value, the crash report will be purged or perserved for future read.
    ///
    /// The SDK calls this method on a background thread. The implementation is free to choice any thread
    /// for executing the  `completion`.
    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool)

    /// Injects custom data for describing the application state in the crash report.
    /// This data will be attached to produced crash report and will be available in `DDCrashReport`.
    ///
    /// The SDK calls this method for each significant application state change.
    /// It is called on a background thread and succeeding calls are synchronized.
    func inject(context: Data)
}
