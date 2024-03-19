/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension DDCrashReport: AnyMockable, RandomMockable {
    public static func mockAny() -> DDCrashReport {
        return .mockWith()
    }

    public static func mockRandom() -> DDCrashReport {
        return DDCrashReport(
            date: .mockRandom(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            threads: .mockRandom(),
            binaryImages: .mockRandom(),
            meta: .mockRandom(),
            wasTruncated: .mockRandom(),
            context: .mockRandom()
        )
    }

    public static func mockWith(
        date: Date? = .mockAny(),
        type: String = .mockAny(),
        message: String = .mockAny(),
        stack: String = .mockAny(),
        threads: [DDThread] = .mockAny(),
        binaryImages: [BinaryImage] = .mockAny(),
        meta: Meta = .mockAny(),
        wasTruncated: Bool = .mockAny(),
        context: Data? = .mockAny()
    ) -> DDCrashReport {
        return DDCrashReport(
            date: date,
            type: type,
            message: message,
            stack: stack,
            threads: threads,
            binaryImages: binaryImages,
            meta: meta,
            wasTruncated: wasTruncated,
            context: context
        )
    }
}

extension DDCrashReport.Meta: AnyMockable, RandomMockable {
    public static func mockAny() -> DDCrashReport.Meta {
        return .mockWith()
    }

    public static func mockRandom() -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: .mockRandom(),
            process: .mockRandom(),
            parentProcess: .mockRandom(),
            path: .mockRandom(),
            codeType: .mockRandom(),
            exceptionType: .mockRandom(),
            exceptionCodes: .mockRandom()
        )
    }

    public static func mockWith(
        incidentIdentifier: String? = .mockAny(),
        process: String? = .mockAny(),
        parentProcess: String? = .mockAny(),
        path: String? = .mockAny(),
        codeType: String? = .mockAny(),
        exceptionType: String? = .mockAny(),
        exceptionCodes: String? = .mockAny()
    ) -> DDCrashReport.Meta {
        return DDCrashReport.Meta(
            incidentIdentifier: incidentIdentifier,
            process: process,
            parentProcess: parentProcess,
            path: path,
            codeType: codeType,
            exceptionType: exceptionType,
            exceptionCodes: exceptionCodes
        )
    }
}
