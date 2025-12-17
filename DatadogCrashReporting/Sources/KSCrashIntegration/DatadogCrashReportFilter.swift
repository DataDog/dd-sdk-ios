/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
#else
@_implementationOnly import KSCrashRecording
#endif
// swiftlint:enable duplicate_imports

/// A KSCrash filter that converts crash reports into Datadog's internal format.
///
/// This filter implements KSCrash's `CrashReportFilter` protocol and serves as a
/// transformation layer between KSCrash's raw crash data and Datadog's structured
/// crash report format. It processes crash reports by extracting and restructuring
/// information such as threads, stack traces, binary images, system metadata, and
/// user context.
///
/// ## Processing Pipeline
///
/// 1. Receives raw KSCrash reports
/// 2. Validates report structure
/// 3. Converts to Datadog's `DDCrashReport` format
/// 4. Wraps in `CrashReportDatadog` for further processing
///
/// ## Error Handling
///
/// If a report cannot be converted (invalid format, missing required fields),
/// the original report is passed through and an error is provided to the completion handler.
internal final class DatadogCrashReportFilter: NSObject, CrashReportFilter {
    // Parse timestamp with fractional seconds support
    // KSCrash timestamps use ISO8601 format with microsecond precision (e.g., "2025-10-22T14:14:12.007336Z")
    let dateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Filters and converts crash reports to Datadog's format.
    ///
    /// This method processes each report by converting it from KSCrash's format
    /// to Datadog's internal representation. If conversion fails for any report,
    /// the error is reported but processing continues for remaining reports.
    ///
    /// - Parameters:
    ///   - reports: The KSCrash reports to process
    ///   - onCompletion: Completion handler called with converted reports and any error.
    ///                   Receives `nil` for reports if all conversions failed, otherwise
    ///                   receives converted reports array (may include original reports
    ///                   for items that failed conversion).
    func filterReports(
        _ reports: [CrashReport],
        onCompletion: (([CrashReport]?, (Error)?) -> Void)?
    ) {
        do {
            try onCompletion?(reports.map(parse(report:)), nil)
        } catch {
            onCompletion?(reports, error)
        }
    }

    /// Creates a Datadog crash report from a KSCrash report.
    ///
    /// This initializer converts a KSCrash `CrashReport` into Datadog's internal format,
    /// extracting and structuring crash information including threads, binary images,
    /// system metadata, and user context.
    ///
    /// - Parameter report: The KSCrash crash report to convert
    /// - Throws: `CrashReportException` if the report format is invalid or required fields are missing
    func parse(report: CrashReport) throws -> CrashReport {
        // Validate and extract the type-safe report dictionary
        guard let dict = report.untypedValue as? CrashFieldDictionary else {
            throw CrashReportException(description: "KSCrash report untypedValue is not a CrashDictionary")
        }

        let date = try dateFormatter.date(from: dict.value(forKey: .report, .timestamp))

        // Extract required crash and system information
        let system: CrashFieldDictionary = try dict.value(forKey: .system)
        let crash: CrashFieldDictionary = try dict.value(forKey: .crash)

        // Build crash type string from signal information
        // Format: "SIGNAL_NAME (SIGNAL_CODE)" e.g., "SIGSEGV (SEGV_MAPERR)"
        let signalName: String = try crash.valueIfPresent(forKey: .error, .signal, .name) ?? "<unknown>"
        let signalCodeName: String = try crash.valueIfPresent(forKey: .error, .signal, .codeName) ?? "#0" // PLCrashReporter defaults to #0
        let type = "\(signalName) (\(signalCodeName))"

        // Build metadata with process information
        // Process format: "processName [pid]" or just "[pid]" if name is unavailable
        let meta = try DDCrashReport.Meta(
            incidentIdentifier: dict.value(forKey: .report, .id),
            process: system.valueIfPresent(Int64.self, forKey: .processID).map { id in
                try system.valueIfPresent(String.self, forKey: .processName).map { "\($0) [\(id)]" } ?? "[\(id)]"
            },
            parentProcess: system.valueIfPresent(Int64.self, forKey: .parentProcessID).map { id in
                try system.valueIfPresent(String.self, forKey: .parentProcessName).map { "\($0) [\(id)]" } ?? "[\(id)]"
            },
            path: system.valueIfPresent(forKey: .executablePath),
            codeType: system.valueIfPresent(forKey: .cpuArch),
            exceptionType: signalName,
            exceptionCodes: signalCodeName
        )

        // Extract crash diagnosis message
        let message: String = try crash.valueIfPresent(forKey: .diagnosis) ?? "No crash reason provided"

        // Transform binary images (loaded libraries/frameworks)
        // Extract memory address ranges and distinguish system vs. user libraries
        let binaryImages: [BinaryImage] = try dict.value([CrashFieldDictionary].self, forKey: .binaryImages).compactMap { image in
            guard let path: NSString = try image.valueIfPresent(forKey: .name) else {
                return nil
            }

            let imageAddress: UInt64 = try image.value(forKey: .imageAddress)
            let imageSize: UInt64 = try image.value(forKey: .imageSize)
            let cpuType: cpu_type_t = try image.value(forKey: .cpuType)
            let cpuSubType: cpu_subtype_t = try image.value(forKey: .cpuSubType)
            let architecture = String(cString: kscpu_archForCPU(cpuType, cpuSubType))

            return try BinaryImage(
                libraryName: path.lastPathComponent,
                uuid: image.value(forKey: .uuid),
                architecture: architecture,
                path: path,
                loadAddress: imageAddress,
                maxAddress: imageAddress + imageSize
            )
        }

        var wasTruncated = false

        // Transform thread information with stack traces
        // Each thread contains a backtrace showing the call stack at crash time
        let threads: [DDThread] = try crash.value([CrashFieldDictionary].self, forKey: .threads).map { thread in
            // Format each stack frame: "index objectName instructionAddr objectAddr + offset"
            let backtrace: [String] = try thread.value([CrashFieldDictionary].self, forKey: .backtrace, .contents).enumerated().compactMap { index, frame in
                let instructionAddr: Int64 = try frame.value(forKey: .instructionAddr)

                guard
                    let objectAddr: Int64 = try frame.valueIfPresent(forKey: .objectAddr),
                    let objectName: NSString = try frame.valueIfPresent(forKey: .objectName)
                else {
                    return String(format: "%-4ld ??? 0x%016llx 0x0 + 0", index, instructionAddr)
                }

                // Format: frame_index (4 chars left-aligned) + library_name (35 chars left-aligned) + instruction_addr + image_base_addr + offset
                return String(format: "%-4ld %-35@ 0x%016llx 0x%016llx + %lld", index, objectName, instructionAddr, objectAddr, instructionAddr - objectAddr)
            }

            let index: Int64 = try thread.value(forKey: .index)
            wasTruncated = try wasTruncated || thread.valueIfPresent(forKey: .backtrace, .truncated) ?? false

            return try DDThread(
                name: "Thread \(index)",
                stack: backtrace.joined(separator: "\n"),
                crashed: thread.value(forKey: .crashed),
                state: nil // TODO: RUMM-1462 Send registers state for crashed thread
            )
        }

        // Extract primary stack trace from crashed thread
        // This is used as the main stack trace for the crash report
        let stack = threads.first(where: { $0.crashed })?.stack
            ?? threads.first?.stack
            ?? "???"

        // Extract injected context.
        // Context is allowed to be missing but not malformed.
        let context = try dict.valueIfPresent(CrashFieldDictionary.self, forKey: .user).map {
            try JSONSerialization.data(withJSONObject: $0)
        }

        return AnyCrashReport(
            DDCrashReport(
                date: date,
                type: type,
                message: message,
                stack: stack,
                threads: threads,
                binaryImages: binaryImages,
                meta: meta,
                wasTruncated: wasTruncated,
                context: context,
                additionalAttributes: nil
            )
        )
    }
}

extension BinaryImage {
    init(
        libraryName: String,
        uuid: String,
        architecture: String,
        path: NSString,
        loadAddress: UInt64,
        maxAddress: UInt64
    ) {
        #if targetEnvironment(simulator)
        // Simulator: system images are in Xcode.app/Contents/Developer/Platforms/ or .simruntime bundles (Xcode 16+)
        let isSystemLibrary = path.contains("/Contents/Developer/Platforms/") || path.contains("simruntime")
        #else
        // Device: user images are in /var/containers/Bundle/Application/, everything else is system
        let isSystemLibrary = !path.contains("/Bundle/Application/")
        #endif
        self.init(
            libraryName: libraryName,
            uuid: uuid,
            architecture: architecture,
            isSystemLibrary: isSystemLibrary,
            loadAddress: String(format: "0x%016llx", loadAddress),
            maxAddress: String(format: "0x%016llx", maxAddress)
        )
    }
}
