/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal

@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

class SegmentRequestBuilderTests: XCTestCase {
    private let rumContext: RUMContext = .mockRandom() // all records must reference the same RUM context
    private var mockEvents: [Event] {
        let records = [
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 5)),
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 10)),
            EnrichedRecord(context: .mockWith(rumContext: self.rumContext), records: .mockRandom(count: 15)),
        ]
        return records.map { .mockWith(data: try! JSONEncoder().encode($0)) }
    }

    func testItCreatesPOSTRequest() throws {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        let request = try builder.request(for: mockEvents, with: .mockAny())

        // Then
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testItSetsIntakeURL() {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site))
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        XCTAssertEqual(try url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/replay")
        XCTAssertEqual(try url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/replay")
        XCTAssertEqual(try url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/replay")
    }

    func testItSetsCustomIntakeURL() {
        // Given
        let randomURL: URL = .mockRandom()
        let builder = SegmentRequestBuilder(customUploadURL: randomURL, telemetry: TelemetryMock())

        // When
        func url(for site: DatadogSite) throws -> String {
            let request = try builder.request(for: mockEvents, with: .mockWith(site: site))
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then
        let expectedURL = randomURL.absoluteStringWithoutQuery
        XCTAssertEqual(try url(for: .us1), expectedURL)
        XCTAssertEqual(try url(for: .us3), expectedURL)
        XCTAssertEqual(try url(for: .us5), expectedURL)
        XCTAssertEqual(try url(for: .eu1), expectedURL)
        XCTAssertEqual(try url(for: .ap1), expectedURL)
        XCTAssertEqual(try url(for: .us1_fed), expectedURL)
    }

    func testItSetsNoQueryParameters() throws {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockRandom()

        // When
        let request = try builder.request(for: mockEvents, with: context)

        // Then
        XCTAssertEqual(request.url!.query, nil)
    }

    func testItSetsHTTPHeaders() throws {
        let randomApplicationName: String = .mockRandom(among: .alphanumerics)
        let randomVersion: String = .mockRandom(among: .decimalDigits)
        let randomSource: String = .mockRandom(among: .alphanumerics)
        let randomSDKVersion: String = .mockRandom(among: .alphanumerics)
        let randomClientToken: String = .mockRandom()
        let randomDeviceName: String = .mockRandom()
        let randomDeviceOSName: String = .mockRandom()
        let randomDeviceOSVersion: String = .mockRandom()

        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())
        let context: DatadogContext = .mockWith(
            clientToken: randomClientToken,
            version: randomVersion,
            source: randomSource,
            sdkVersion: randomSDKVersion,
            applicationName: randomApplicationName,
            device: .mockWith(
                name: randomDeviceName,
                osName: randomDeviceOSName,
                osVersion: randomDeviceOSVersion
            )
        )

        // When
        let request = try builder.request(for: mockEvents, with: context)

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: #"multipart\/form-data; boundary=([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})"#))
        XCTAssertEqual(
            request.allHTTPHeaderFields?["User-Agent"],
            """
            \(randomApplicationName)/\(randomVersion) CFNetwork (\(randomDeviceName); \(randomDeviceOSName)/\(randomDeviceOSVersion))
            """
        )
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomSource)
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], randomSDKVersion)
        XCTAssertNil(request.allHTTPHeaderFields?["Content-Encoding"], "It must us no compression, because multipart file is compressed separately")
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-REQUEST-ID"]?.matches(regex: .uuidRegex), true)
    }

    func testItSetsHTTPBodyInExpectedFormat() throws {
        // Given
        let multipartSpy = MultipartBuilderSpy()
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock(), multipartBuilder: multipartSpy)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let context0: RUMContext = .mockRandom()
        let context1: RUMContext = .mockRandom()
        let events = try [
            EnrichedRecord(context: .mockWith(rumContext: context0), records: .mockRandom(count: 5)),
            EnrichedRecord(context: .mockWith(rumContext: context0), records: .mockRandom(count: 10)),
            EnrichedRecord(context: .mockWith(rumContext: context0), records: .mockRandom(count: 15)),
            EnrichedRecord(context: .mockWith(rumContext: context1), records: .mockRandom(count: 5)),
            EnrichedRecord(context: .mockWith(rumContext: context1), records: .mockRandom(count: 10)),
            EnrichedRecord(context: .mockWith(rumContext: context1), records: .mockRandom(count: 15)),
        ].map {
            try Event.mockWith(data: encoder.encode($0))
        }

        // When
        let request = try builder.request(for: events, with: .mockWith(source: "ios"))

        // Then
        let contentType = try XCTUnwrap(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertTrue(contentType.matches(regex: "multipart/form-data; boundary=\(multipartSpy.boundary)"))
        XCTAssertEqual(multipartSpy.formFiles.count, 3)

        let file0 = multipartSpy.formFiles[0]
        XCTAssertEqual(file0.filename, "file0")
        XCTAssertEqual(file0.mimeType, "application/octet-stream")

        let segment0 = try decoder.decode(SRSegment.self, from: XCTUnwrap(zlib.decode(file0.data)))
        XCTAssertEqual(segment0.application.id, context0.applicationID)
        XCTAssertEqual(segment0.session.id, context0.sessionID)
        XCTAssertEqual(segment0.view.id, context0.viewID)
        XCTAssertEqual(segment0.source, .ios)
        XCTAssertEqual(segment0.recordsCount, 30)

        let file1 = multipartSpy.formFiles[1]
        XCTAssertEqual(file1.filename, "file1")
        XCTAssertEqual(file1.mimeType, "application/octet-stream")

        let segment1 = try decoder.decode(SRSegment.self, from: XCTUnwrap(zlib.decode(file1.data)))
        XCTAssertEqual(segment1.application.id, context1.applicationID)
        XCTAssertEqual(segment1.session.id, context1.sessionID)
        XCTAssertEqual(segment1.view.id, context1.viewID)
        XCTAssertEqual(segment1.source, .ios)
        XCTAssertEqual(segment1.recordsCount, 30)

        let blob = multipartSpy.formFiles[2]
        XCTAssertEqual(blob.filename, "blob")
        XCTAssertEqual(blob.mimeType, "application/json")
        let metadata = try decoder.decode([Metadata].self, from: blob.data)
        XCTAssertEqual(metadata.count, 2)
        XCTAssertEqual(metadata[0].application.id, context0.applicationID)
        XCTAssertEqual(metadata[0].session.id, context0.sessionID)
        XCTAssertEqual(metadata[0].view.id, context0.viewID)
        XCTAssertNil(metadata[0].records)
        XCTAssertGreaterThanOrEqual(metadata[0].rawSegmentSize, metadata[0].compressedSegmentSize)
        XCTAssertEqual(metadata[1].application.id, context1.applicationID)
        XCTAssertEqual(metadata[1].session.id, context1.sessionID)
        XCTAssertEqual(metadata[1].view.id, context1.viewID)
        XCTAssertNil(metadata[1].records)
        XCTAssertGreaterThanOrEqual(metadata[1].rawSegmentSize, metadata[1].compressedSegmentSize)

        // This definition is only used for assertion as it does not exist in the shared
        // schema yet.
        struct Metadata: Decodable {
            let application: SRSegment.Application
            let end: Int64
            let hasFullSnapshot: Bool?
            let indexInView: Int64?
            let records: [SRRecord]?
            let recordsCount: Int64
            let session: SRSegment.Session
            let source: SRSegment.Source
            let start: Int64
            let view: SRSegment.View
            let rawSegmentSize: Int
            let compressedSegmentSize: Int

            enum CodingKeys: String, CodingKey {
                case application = "application"
                case end = "end"
                case hasFullSnapshot = "has_full_snapshot"
                case indexInView = "index_in_view"
                case records = "records"
                case recordsCount = "records_count"
                case session = "session"
                case source = "source"
                case start = "start"
                case view = "view"
                case rawSegmentSize = "raw_segment_size"
                case compressedSegmentSize = "compressed_segment_size"
            }
        }
    }

    func testWhenBatchDataIsMalformed_itThrows() {
        // Given
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: TelemetryMock())

        // When, Then
        XCTAssertThrowsError(try builder.request(for: [.mockWith(data: "abc".utf8Data)], with: .mockAny()))
    }

    func testWhenSourceIsInvalid_itSendsErrorTelemetry() throws {
        // Given
        let telemetry = TelemetryMock()
        let builder = SegmentRequestBuilder(customUploadURL: nil, telemetry: telemetry)

        // When
        _ = try builder.request(for: mockEvents, with: .mockWith(source: "invalid source"))

        // Then
        XCTAssertEqual(
            telemetry.description,
            """
            Telemetry logs:
             - [error] [SR] Could not create segment source from provided string 'invalid source', kind: nil, stack: nil
            """
        )
    }
}
#endif
