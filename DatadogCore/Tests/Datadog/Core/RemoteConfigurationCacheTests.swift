/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class RemoteConfigurationCacheTests: XCTestCase {
    private var coreDir = temporaryUniqueCoreDirectory()

    override func setUp() {
        super.setUp()
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
    }

    override func tearDown() {
        coreDir.delete()
        super.tearDown()
    }

    // MARK: Read at init

    func testReturnsNilWhenNoCacheExists() {
        let cache = RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory)
        XCTAssertNil(cache.data)
        XCTAssertNil(cache.loadError)
    }

    // MARK: Persistence across instances (simulates app relaunch)

    func testDataReadBackOnNextInit() {
        let payload = Data("{\"session_sample_rate\":50}".utf8)

        // First "launch": save data
        let cache1 = RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory)
        cache1.save(payload)

        // Second "launch": a fresh instance must read it back
        let cache2 = RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory)
        XCTAssertEqual(cache2.data, payload)
        XCTAssertNil(cache2.loadError)
    }

    func testSaveOverwritesPreviousFile() {
        let first  = Data("{\"v\":1}".utf8)
        let second = Data("{\"v\":2}".utf8)

        RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory).save(first)
        RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory).save(second)

        let cache = RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory)
        XCTAssertEqual(cache.data, second)
    }

    func testDifferentIDsUseDifferentFiles() {
        let payload1 = Data("{\"v\":1}".utf8)
        let payload2 = Data("{\"v\":2}".utf8)

        RemoteConfigurationCache(id: "id-one", directory: coreDir.coreDirectory).save(payload1)
        RemoteConfigurationCache(id: "id-two", directory: coreDir.coreDirectory).save(payload2)

        XCTAssertEqual(RemoteConfigurationCache(id: "id-one", directory: coreDir.coreDirectory).data, payload1)
        XCTAssertEqual(RemoteConfigurationCache(id: "id-two", directory: coreDir.coreDirectory).data, payload2)
    }

    // MARK: Failure resilience

    func testSaveReturnsNilOnSuccess() {
        let cache = RemoteConfigurationCache(id: "test-id", directory: coreDir.coreDirectory)
        XCTAssertNil(cache.save(Data("{\"k\":\"v\"}".utf8)))
    }

    func testSaveReturnsErrorWhenDirectoryMissing() {
        let missing = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let cache   = RemoteConfigurationCache(id: "test-id", directory: missing)
        XCTAssertNotNil(cache.save(Data("{\"k\":\"v\"}".utf8)))
    }

    func testLoadErrorSetWhenFileIsCorrupt() throws {
        // Write a valid file, then revoke read permission so Data(contentsOf:) fails.
        let id = "corrupt-id"
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("\(id).json")
        try Data("{\"v\":1}".utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        let cache = RemoteConfigurationCache(id: id, directory: coreDir.coreDirectory)
        XCTAssertNil(cache.data)
        XCTAssertNotNil(cache.loadError)
    }
}
