/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class FlagsEvaluationContextTests: XCTestCase {
    func testOptOutTimestampNormalizesProlepticGregorianDates() throws {
        let cases: [(String, Int64, Int32)] = [
            ("0000-01-01T00:00:00Z", -62_167_219_200, 0),
            ("0000-02-29T00:00:00Z", -62_162_121_600, 0),
            ("0000-03-01T00:00:00+00:01", -62_162_035_260, 0),
            ("0000-01-01T00:00:00.123456789-00:00", -62_167_219_200, 123_456_789),
            ("1582-10-10T00:00:00Z", -12_219_724_800, 0),
            ("1582-10-04T23:59:59-00:01", -12_220_156_741, 0),
            ("1582-10-15T00:00:00+00:01", -12_219_292_860, 0),
            ("2000-03-01T00:15:00+01:00", 951_866_100, 0),
            ("1900-03-01T00:15:00+01:00", -2_203_893_900, 0),
            ("2026-01-01T00:00:00+23:59", 1_767_139_260, 0),
            ("2025-12-31T23:59:00-23:59", 1_767_311_880, 0),
            ("2026-10-19t08:00:00.1234567899-04:00", 1_792_411_200, 123_456_789),
            ("2026-10-19T12:00:00.1200000000z", 1_792_411_200, 120_000_000),
            ("2026-10-19T12:00:00.0000000009Z", 1_792_411_200, 0),
            ("9999-12-31T23:58:59.9999999999-00:01", 253_402_300_799, 999_999_999),
            ("9999-12-31T23:59:59.999999999Z", 253_402_300_799, 999_999_999),
            ("2026-10-19T12:00:00.5Z", 1_792_411_200, 500_000_000),
            ("2026-10-19T12:00:00.123Z", 1_792_411_200, 123_000_000),
            ("2026-10-19T12:00:00.000001Z", 1_792_411_200, 1_000),
            ("1970-01-01T00:00:00Z", 0, 0),
            ("1969-12-31T23:59:59.1234567899Z", -1, 123_456_789)
        ]
        for (input, seconds, nanoseconds) in cases {
            let instant = try OptOutInstant(rfc3339: input)
            XCTAssertEqual(instant.seconds, seconds, input)
            XCTAssertEqual(instant.nanoseconds, nanoseconds, input)
        }
    }

    func testOptOutTimestampRejectsInvalidGregorianDatesAndUTCOverflow() {
        for input in [
            "0000-01-01T00:00:00+00:01",
            "9999-12-31T23:59:59-00:01",
            "9999-12-31T23:59:00-00:01", // Exactly 10000-01-01T00:00:00Z.
            "1500-02-29T00:00:00Z",
            "1900-02-29T00:00:00Z",
            "2026-04-31T00:00:00Z",
            "2026-00-01T00:00:00Z",
            "2026-13-01T00:00:00Z",
            "2026-01-00T00:00:00Z",
            "2026-01-01T24:00:00Z",
            "2026-01-01T00:60:00Z",
            "2026-01-01T00:00:60Z",
            "2026-01-01T00:00:00+24:00",
            "2026-01-01T00:00:00+00:60"
        ] {
            XCTAssertThrowsError(try OptOutInstant(rfc3339: input), input)
        }
    }

    func testOptOutTimestampRequiresCompleteFormat() {
        for input in [
            "2026-01-01", "2026-01-01T00:00Z", "2026-01-01T00:00:00",
            "2026-1-1T00:00:00Z", "2026-01-01 00:00:00Z",
            "2026-01-01T00:00:00.Z", "2026-01-01T00:00:00+0000",
            "2026-01-01T00:00:00Z\n", " 2026-01-01T00:00:00Z",
            "２０２６-01-01T00:00:00Z"
        ] {
            XCTAssertThrowsError(try OptOutInstant(rfc3339: input), input)
        }
    }
    func testImmediateOptOutRejectsCutoffWithoutExplicitImmediateMode() throws {
        let cutoffs: [Any?] = [nil, "2026-10-21T12:00:00Z", "invalid", "", NSNull(), true, 42, [:], []]
        let modes: [String?] = [nil, "immediate", "future_experiments_only"]
        for mode in modes {
            for cutoff in cutoffs {
                var options: [String: Any] = ["experimentation_opt_out": true]
                if let mode { options["experimentation_opt_out_mode"] = mode }
                if let cutoff { options["dd_experimentation_opt_out_at"] = cutoff }
                let attributes: [String: Any] = ["flags": [:], "evaluation_options": options]
                let bytes = try JSONSerialization.data(withJSONObject: ["data": ["attributes": attributes]])
                let response = try JSONDecoder().decode(FlagAssignmentsResponse.self, from: bytes)
                XCTAssertEqual(
                    ExperimentationOptOut.accepts(response, for: .immediate),
                    mode == "immediate" || (mode == nil && cutoff == nil),
                    "\(options)"
                )
            }
        }
    }

    func testAdmissionRequiresCompatibleBooleanAndMode() throws {
        let cases: [(String?, Bool, Bool)] = [
            (nil, true, false),
            (#"{"experimentation_opt_out":false}"#, true, false),
            (#"{"experimentation_opt_out":"true"}"#, false, false),
            (#"{"experimentation_opt_out":null}"#, true, false),
            (#"{"experimentation_opt_out":true}"#, false, true),
            (#"{"experimentation_opt_out_mode":true,"experimentation_opt_out":true}"#, false, false),
            (#"{"experimentation_opt_out_mode":"future_experiments_only","experimentation_opt_out":true}"#, false, false)
        ]
        for (options, unfiltered, immediate) in cases {
            let response = try response(options: options)
            XCTAssertEqual(ExperimentationOptOut.accepts(response, for: nil), unfiltered, String(describing: options))
            XCTAssertEqual(ExperimentationOptOut.accepts(response, for: .immediate), immediate, String(describing: options))
        }
        for mode in ["unknown", "", "immediate", "future_experiments_only", true, 42, [:], [], NSNull()] as [Any] {
            let options = try JSONSerialization.data(withJSONObject: ["experimentation_opt_out_mode": mode])
            let response = try response(options: String(decoding: options, as: UTF8.self))
            XCTAssertFalse(ExperimentationOptOut.accepts(response, for: nil), "\(mode)")
            XCTAssertFalse(ExperimentationOptOut.accepts(response, for: .immediate), "\(mode)")
        }
    }

    func testUnfilteredAdmissionRejectsMalformedOptionsAndCutoffs() throws {
        for (options, accepted) in [("null", true), (#""immediate""#, false), ("42", false), ("[]", false), (#"{"experimentation_opt_out":1}"#, false)] {
            XCTAssertEqual(ExperimentationOptOut.accepts(try response(options: options), for: nil), accepted, options)
        }
        for cutoff in ["2026-10-21T12:00:00Z", "invalid", "", NSNull(), true, 42, [:], []] as [Any] {
            let options = try JSONSerialization.data(withJSONObject: ["dd_experimentation_opt_out_at": cutoff])
            XCTAssertFalse(ExperimentationOptOut.accepts(try response(options: String(decoding: options, as: UTF8.self)), for: nil), "\(cutoff)")
        }
    }

    func testFutureAdmissionRequiresTypedModeAndExactCutoff() throws {
        let cutoff = "2026-10-21T12:00:00.123456789Z"
        let cases: [(Any?, Any?, Bool)] = [
            (nil, nil, false), (true, cutoff, false), ("immediate", cutoff, false),
            ("future_experiments_only", nil, false), ("future_experiments_only", 123, false),
            ("future_experiments_only", "invalid", false),
            ("future_experiments_only", "2026-10-21T12:00:00.123456788Z", false),
            ("future_experiments_only", "2026-10-21T12:00:00.123456790Z", false),
            ("future_experiments_only", "2026-10-22T12:00:00Z", false),
            ("future_experiments_only", "2026-10-21T14:00:00.123456789+02:00", true),
            ("future_experiments_only", "2026-10-21T12:00:00.1234567890Z", true),
            ("future_experiments_only", "2026-10-21T12:00:00.123456789123Z", true),
            ("future_experiments_only", cutoff, true)
        ]
        for (mode, acknowledged, accepted) in cases {
            var options: [String: Any] = [:]
            if let mode { options["experimentation_opt_out_mode"] = mode }
            if let acknowledged { options["dd_experimentation_opt_out_at"] = acknowledged }
            let bytes = try JSONSerialization.data(withJSONObject: options)
            XCTAssertEqual(ExperimentationOptOut.accepts(try response(options: String(decoding: bytes, as: UTF8.self)), for: .futureExperimentsOnly(cutoff: try OptOutInstant(rfc3339: cutoff))), accepted, "\(options)")
        }
    }

    private func response(options: String?) throws -> FlagAssignmentsResponse {
        var attributes: [String: Any] = ["flags": [:]]
        if let options {
            attributes["evaluation_options"] = try JSONSerialization.jsonObject(with: Data(options.utf8), options: .fragmentsAllowed)
        }
        let bytes = try JSONSerialization.data(withJSONObject: ["data": ["attributes": attributes]])
        return try JSONDecoder().decode(FlagAssignmentsResponse.self, from: bytes)
    }
}
